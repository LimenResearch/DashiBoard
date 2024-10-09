# Helpers to query table created by DataIngestion

function table_schema(repo, tbl::AbstractString)
    return DBInterface.execute(Tables.schema, repo, "FROM $tbl LIMIT 0;")
end

function categorical_summary(repo, tbl::AbstractString, var::AbstractString)
    query = """
    SELECT DISTINCT "$var" AS value FROM $tbl;
    """
    return DBInterface.execute(res -> map(only, res), repo, query)
end

function numerical_summary(repo, tbl::AbstractString, var::AbstractString; length = 100, sigdigits = 2)
    query = """
    SELECT min("$var") AS x0, max("$var") AS x1 FROM $tbl;
    """
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

function summarize(repo, tbl)
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
