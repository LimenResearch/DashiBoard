# TODO: support window functions with additional arguments
# TODO: support multiple window functions within a card?
const WINDOW_FUNCTIONS = OrderedDict{String, AggClosure}(
    "rank" => Agg.rank,
    "percent_rank" => Agg.percent_rank,
    "row_number" => Agg.row_number,
)

StructUtils.structlike(::DashiStyle, ::Type{<:AggClosure}) = false

"""
    struct WindowFunctionCard <: Card
        method::AggClosure
        order_by::Vector{String}
        group_by::Vector{String} = String[]
        output::String
    end

Add new column with output of window function.
"""
@kwarg struct WindowFunctionCard <: SQLCard
    method::AggClosure & (
        dashi = EmptyTaggedObjectIR(objects = WINDOW_FUNCTIONS),
        lift = Fix2(lift_simple_method, WINDOW_FUNCTIONS),
        lower = Fix2(lower_simple_method, WINDOW_FUNCTIONS),
    )
    order_by::Vector{String} & (dashi = NONEMPTY_VARIABLES_DEF,)
    group_by::Vector{String} = String[] & (dashi = VARIABLES_DEF,)
    output::String & (dashi = StringIR(minLength = 1),)
end

## SQLCard interface

SourceVariables(wfc::WindowFunctionCard) = SourceVariables(; wfc.order_by, wfc.group_by)

output_spec(wfc::WindowFunctionCard) = OutputSpec([wfc.output])

function train(
        ::Repository, ::WindowFunctionCard, ::AbstractString, ::AbstractPrimaryKey;
        schema::Maybe{AbstractString} = nothing
    )
    return CardState()
end

function evaluate(
        repository::Repository,
        wfc::WindowFunctionCard,
        ::CardState,
        (source, destination)::Pair,
        id_var::AbstractPrimaryKey;
        schema::Maybe{AbstractString} = nothing
    )

    query = From(source) |>
        Partition(; order_by = Get.(wfc.order_by), by = Get.(wfc.group_by)) |>
        Select(id_var => Get(id_var), wfc.output => wfc.method())

    replace_table(repository, query, destination; schema)
    return [wfc.output]
end
