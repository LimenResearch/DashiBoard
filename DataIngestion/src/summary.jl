# Helpers to query table created by DataIngestion

function table_schema(repository::Repository, tbl::AbstractString; schema = nothing)
    query = From(tbl) |> Limit(0)
    return DBInterface.execute(Tables.schema, repository, query; schema)
end

function categorical_summary(repository::Repository, tbl::AbstractString, var::AbstractString; schema = nothing)
    query = From(tbl) |> Group(Get(var)) |> Order(Get(var))
    return DBInterface.execute(res -> map(only, res), repository, query; schema)
end

function numerical_summary(
        repository::Repository, tbl::AbstractString, var::AbstractString;
        schema = nothing, length = 100, sigdigits = 2
    )
    query = From(tbl) |> Select("x0" => Fun.min(Get(var)), "x1" => Fun.max(Get(var)))
    (; x0, x1) = DBInterface.execute(first, repository, query; schema)
    diff = x1 - x0
    step = if x0 isa Integer && diff ≤ length
        1
    else
        round(diff / length; sigdigits)
    end
    return (min = x0, max = x1, step = step)
end

isnumerical(::Type{<:Number}) = true
isnumerical(::Type{Bool}) = false
isnumerical(::Type) = false

struct VariableSummary
    name::String
    type::String
    eltype::String
    summary::Any
end

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
    summarize(repository::Repository, tbl::AbstractString; schema = nothing)

Compute summaries of variables in table `tbl` within the database `repository.db`.
The summary of a variable depends on its type, according to the following rules.

- Categorical variable => list of unique types.
- Continuous variable => extrema.
"""
function summarize(repository::Repository, tbl::AbstractString; schema = nothing)
    (; names, types) = table_schema(repository, tbl; schema)
    return map(names, types) do name, eltype
        T = nonmissingtype(eltype)
        var = string(name)
        if isnumerical(T)
            summary = numerical_summary(repository, tbl, var; schema)
            type = "numerical"
        else
            summary = categorical_summary(repository, tbl, var; schema)
            type = "categorical"
        end
        eltype = stringify_type(T)
        return VariableSummary(var, type, eltype, summary)
    end
end
