# TODO: support window functions with additional arguments
# TODO: support multiple window functions within a card?
const WINDOW_FUNCTIONS = OrderedDict{String, SQLNode}(
    "rank" => Agg.rank(),
    "percent_rank" => Agg.percent_rank(),
    "row_number" => Agg.row_number(),
)

StructUtils.structlike(::DashiStyle, ::Type{<:SQLNode}) = false

"""
    struct WindowFunctionCard <: Card
        method::SQLNode
        order_by::Vector{String}
        group_by::Vector{String} = String[]
        output::String
    end

Add new column with output of window function.
"""
@kwarg struct WindowFunctionCard <: SQLCard
    method::SQLNode & (
        dashi = type_schema(keys(WINDOW_FUNCTIONS), additionalProperties = false),
        lift = Fix2(get_method, WINDOW_FUNCTIONS),
        lower = Fix2(lower_method, WINDOW_FUNCTIONS),
    )
    order_by::Vector{String} & (dashi = JSON_NONEMPTY_VARIABLES,)
    group_by::Vector{String} = String[] & (dashi = JSON_VARIABLES,)
    output::String & (dashi = json_string(minLength = 1),)
end

get_metadata(wfc::WindowFunctionCard) = construct(StringDict, wfc)

WindowFunctionCard(c::AbstractDict) = construct(WindowFunctionCard, c)

## SQLCard interface

SourceVariables(wfc::WindowFunctionCard) = SourceVariables(; wfc.order_by, wfc.group_by)

OutputVariables(wfc::WindowFunctionCard) = OutputVariables([wfc.output])

function train(
        ::Repository, ::WindowFunctionCard, ::AbstractString, ::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )
    return CardState()
end

function evaluate(
        repository::Repository,
        wfc::WindowFunctionCard,
        ::CardState,
        (source, destination)::Pair,
        id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )

    query = From(source) |>
        Partition(; order_by = Get.(wfc.order_by), by = Get.(wfc.group_by)) |>
        Select(id_var => Get(id_var), wfc.output => wfc.method)

    replace_table(repository, query, destination; schema)
    return [wfc.output]
end

## UI representation

function CardWidget(
        ::Type{WindowFunctionCard}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    )

    config = CardWidgetConfigs(parse_toml_config("config", key))
    c = combine_options(config.widget_configs; global_options, user_options)

    methods = collect(keys(WINDOW_FUNCTIONS))

    fields = [
        Widget("method", c; options = methods),
        Widget("order_by", c),
        Widget("group_by", c, required = false),
        Widget("output", c, value = "output"),
    ]

    return CardWidget(key, fields, OutputSpec("output"))
end
