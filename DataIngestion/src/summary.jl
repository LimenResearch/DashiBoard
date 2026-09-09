# Helpers to query table created by DataIngestion

function table_schema(
        repository::Repository, tbl::AbstractString;
        schema::Maybe{AbstractString} = nothing
    )
    query = From(tbl) |> Limit(0)
    return DBInterface.execute(Tables.schema, repository, query; schema)
end

isnumerical(::Type{<:Number}) = true
isnumerical(::Type{Bool}) = false
isnumerical(::Type) = false

mutable struct VariableSummary
    const name::String
    const type::String
    const eltype::String
    summary::Any
end

function VariableSummary(name::AbstractString, type::AbstractString, eltype::AbstractString)
    return VariableSummary(name, type, eltype, nothing)
end

const SUMMARY_FUNCTIONS = Dict(
    "numerical" => SQLMacro("list_extrema", ["x"], "list_value(min(x), max(x))"),
    "categorical" => SQLMacro("list_unique_sorted", ["x"], "list(DISTINCT x ORDER BY x ASC)"),
)

const POST_PROCESSING_FUNCTIONS = Dict(
    "numerical" => NamedTuple{(:min, :max)},
    "categorical" => identity,
)

agg_selection(vs::VariableSummary) = vs.name => Agg(SUMMARY_FUNCTIONS[vs.type].name, Get(vs.name))
post_processor(vs::VariableSummary) = POST_PROCESSING_FUNCTIONS[vs.type]

function stringify_type(::Type{T}) where {T}
    T <: Bool && return "bool"
    T <: Integer && return "int"
    T <: AbstractFloat && return "float"
    T <: AbstractString && return "string"
    T <: Date && return "date"
    T <: Time && return "time"
    T <: DateTime && return "datetime"
    return string(T)
end

"""
    summarize(
        repository::Repository, tbl::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing
    )

Compute summaries of variables in table `tbl` within the database `repository.db`.
The summary of a variable depends on its type, according to the following rules.

- Categorical variable => list of unique types.
- Continuous variable => extrema.
"""
function summarize(
        repository::Repository, tbl::AbstractString;
        schema::Maybe{AbstractString} = nothing
    )

    tbl_schema = table_schema(repository, tbl; schema)
    names, types = collect(tbl_schema.names), collect(tbl_schema.types)

    summaries = map(names, types) do name, eltype
        T = nonmissingtype(eltype)
        type = isnumerical(T) ? "numerical" : "categorical"
        eltype = stringify_type(T)
        return VariableSummary(string(name), type, eltype)
    end

    query = From(tbl) |> Group() |> Select(args = agg_selection.(summaries))

    DuckDBUtils.execute_with_macros(repository, values(SUMMARY_FUNCTIONS), query; schema) do res
        row = first(res)
        for s in summaries
            val = Tables.getcolumn(row, Symbol(s.name))
            s.summary = post_processor(s)(val)
        end
    end

    return summaries
end
