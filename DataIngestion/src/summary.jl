# Helpers to query table created by DataIngestion

function table_schema(repo::Repository, tbl::AbstractString)
    query = From(tbl) |> Limit(0)
    return DBInterface.execute(Tables.schema, repo, query)
end

function categorical_summary(repo::Repository, tbl::AbstractString, var::AbstractString)
    query = From(tbl) |> Group(Get[var]) |> Order(Get[var])
    return DBInterface.execute(res -> map(only, res), repo, query)
end

function numerical_summary(repo::Repository, tbl::AbstractString, var::AbstractString; length = 100, sigdigits = 2)
    query = From(tbl) |> Select("x0" => Fun.min(Get[var]), "x1" => Fun.max(Get[var]))
    (; x0, x1) = DBInterface.execute(first, repo, query)
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
    summary::Any
end

"""
    summarize(repo::Repository, tbl::AbstractString)

Compute summaries of variables in table `tbl` within the database `repo.db`.
The summary of a variable depends on its type, according to the following rules.

- Categorical variable => list of unique types.
- Continuous variable => extrema.
"""
function summarize(repo::Repository, tbl::AbstractString)
    schema = table_schema(repo, tbl)
    return map(schema.names, schema.types) do name, eltype
        var = string(name)
        if isnumerical(nonmissingtype(eltype))
            summary = numerical_summary(repo, tbl, var)
            type = "numerical"
        else
            summary = categorical_summary(repo, tbl, var)
            type = "categorical"
        end
        return VariableSummary(var, type, summary)
    end
end
