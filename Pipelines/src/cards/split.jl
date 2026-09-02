abstract type SplittingMethod <: AbstractMethod end

abstract type OrderedSplittingMethod <: SplittingMethod end

abstract type UnorderedSplittingMethod <: SplittingMethod end

# TODO: add unordered methods

@tags struct PercentileMethod <: OrderedSplittingMethod
    percentile::Float64 & (dashi = NumberIR(minimum = 0, maximum = 1),)
end

get_sql(m::PercentileMethod) = Fun.case(Agg.percent_rank() .≤ m.percentile, 1, 2)

@kwarg struct TilesMethod <: OrderedSplittingMethod
    tiles::Vector{Int} & (
        dashi = ArrayIR{Int}(items = IntegerIR(enum = [1, 2]), minItems = 1),
    )
    repeat::Int = 1 & (dashi = IntegerIR(minimum = 1),)
    tail::Int = 0 & (dashi = IntegerIR(minimum = 0),)
end

function get_sql(m::TilesMethod)
    n = length(m.tiles)
    N = m.repeat * n + m.tail
    vals = Fun.list_value(m.tiles...)
    # work around inconsistency in `%` operator and 1-based indexing in DuckDB
    return Fun.list_extract(vals, Fun."%"(Agg.ntile(N) .- 1, n) .+ 1)
end

const SPLITTING_METHODS = OrderedDict{String, Type}(
    "percentile" => PercentileMethod,
    "tiles" => TilesMethod,
)

@options SplittingMethod SPLITTING_METHODS

"""
    struct SplitCard{M <: SplittingMethod} <: SQLCard
        method::M
        order_by::Vector{String} = String[]
        group_by::Vector{String} = String[]
        output::String = "partition"
    end

Card to split the data into two groups according to a given `method`.

Currently supported methods are
- `tiles` (requires `tiles` argument, e.g., `tiles = [1, 1, 2, 1, 1, 2]`),
- `percentile` (requires `percentile` argument, e.g. `percentile = 0.9`).
"""
@kwarg struct SplitCard{M <: SplittingMethod} <: SQLCard
    method::M
    order_by::Vector{String} = String[] & (dashi = VARIABLES_DEF,)
    group_by::Vector{String} = String[] & (dashi = VARIABLES_DEF,)
    output::String = "partition" & (dashi = StringIR(minLength = 1),)
end

# FIXME: better solution to this escape hatch?
function additional_conditions(::Type{SplitCard})
    enum = findall(T -> T <: OrderedSplittingMethod, SPLITTING_METHODS)
    schema = StringDict(
        "if" => StringDict(
            "properties" => StringDict(
                "method" => StringDict(
                    "properties" => StringDict(
                        "type" => emit_json(StringIR(; enum))
                    )
                )
            ),
        ),
        "then" => StringDict(
            "properties" => StringDict(
                "order_by" => emit_json(NONEMPTY_VARIABLES_DEF)
            )
        )
    )
    return StringDict[schema]
end

## SQLCard interface

SourceVariables(sc::SplitCard) = SourceVariables(; sc.order_by, sc.group_by)

OutputVariables(sc::SplitCard) = OutputVariables([sc.output])

function train(
        ::Repository, ::SplitCard, ::AbstractString, ::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )
    return CardState()
end

function evaluate(
        repository::Repository,
        sc::SplitCard,
        ::CardState,
        (source, destination)::Pair,
        id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )

    query = From(source) |>
        Partition(; order_by = Get.(sc.order_by), by = Get.(sc.group_by)) |>
        Select(id_var => Get(id_var), sc.output => get_sql(sc.method))

    replace_table(repository, query, destination; schema)
    return [sc.output]
end

## UI representation

function CardWidget(
        ::Type{SplitCard}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    )

    config = CardWidgetConfigs(parse_toml_config("config", key))
    c = combine_options(config.widget_configs; global_options, user_options)

    methods = collect(keys(SPLITTING_METHODS))

    fields = vcat(
        [
            Widget("method", c; options = methods),
        ],
        method_dependent_widgets(c, "method", config.methods),
        [
            Widget("order_by", c),
            Widget("group_by", c, required = false),
            Widget("output", c, value = "partition"),
        ]
    )

    return CardWidget(key, fields, OutputSpec("output"))
end
