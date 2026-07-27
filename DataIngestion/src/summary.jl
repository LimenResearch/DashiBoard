# Helpers to query table created by DataIngestion

function table_schema(
        repository::Repository, tbl::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing
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

agg_fn(vs::VariableSummary) = vs.type == "numerical" ? Agg.list_extrema : Agg.list_unique_sorted

agg_selection(vs::VariableSummary) = vs.name => agg_fn(vs)(Get(vs.name))

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
        schema::Union{AbstractString, Nothing} = nothing
    )

    DBInterface.execute(
        Returns(nothing),
        repository,
        "CREATE MACRO IF NOT EXISTS list_unique_sorted(x) AS list(DISTINCT x ORDER BY x ASC);"
    )
    DBInterface.execute(
        Returns(nothing),
        repository,
        "CREATE MACRO IF NOT EXISTS list_extrema(x) AS list_value(min(x), max(x));"
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

    DBInterface.execute(repository, query; schema) do res
        row = first(res)
        for s in summaries
            s.summary = Tables.getcolumn(row, Symbol(s.name))
        end
    end

    return summaries
end
