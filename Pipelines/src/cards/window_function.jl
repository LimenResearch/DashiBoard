# TODO: support window functions with additional arguments
# TODO: support multiple window functions within a card?
const WINDOW_FUNCTIONS = OrderedDict{String, AggClosure}(
    "rank" => Agg.rank,
    "percent_rank" => Agg.percent_rank,
    "row_number" => Agg.row_number,
)

"""
    struct WindowFunctionCard <: Card
        type::String
        method::String
        window_function::SQLNode
        order_by::Vector{String}
        group_by::Vector{String}
        output::String
    end

Add new column with output of window function.
"""
struct WindowFunctionCard <: SQLCard
    type::String
    method::String
    window_function::SQLNode
    order_by::Vector{String}
    group_by::Vector{String}
    output::String
end

const WINDOW_FUNCTION_CARD_CONFIG = CardConfig{WindowFunctionCard}(parse_toml_config("config", "window_function"))

function get_metadata(wfc::WindowFunctionCard)
    return StringDict(
        "type" => wfc.type,
        "method" => wfc.method,
        "order_by" => wfc.order_by,
        "group_by" => wfc.group_by,
        "output" => wfc.output,
    )
end

function WindowFunctionCard(c::AbstractDict)
    type::String = c["type"]
    order_by::Vector{String} = get(c, "order_by", String[])
    group_by::Vector{String} = get(c, "group_by", String[])
    method::String = c["method"]
    window_function::SQLNode = WINDOW_FUNCTIONS[method]()
    output::String = c["output"]
    return WindowFunctionCard(type, method, window_function, order_by, group_by, output)
end

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
        Select(id_var => Get(id_var), wfc.output => wfc.window_function)

    replace_table(repository, query, destination; schema)
    return [wfc.output]
end

## UI representation

function CardWidget(config::CardConfig{WindowFunctionCard}, c::AbstractDict)
    methods = collect(keys(WINDOW_FUNCTIONS))

    fields = [
        Widget("method", c; options = methods),
        Widget("order_by", c),
        Widget("group_by", c, required = false),
        Widget("output", c, value = "output"),
    ]

    return CardWidget(config.key, config.label, fields, OutputSpec("output"))
end
