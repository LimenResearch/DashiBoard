using HTTP: HTTP
using Oxygen: json, @post, serve

using JSON3, DuckDB, Tables

using DataIngestion

allowed_origins = ["Access-Control-Allow-Origin" => "*"]

cors_headers = [
    allowed_origins...,
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST"
]

function CorsHandler(handle)
    return function (req::HTTP.Request)
        # return headers on OPTIONS request
        if HTTP.method(req) == "OPTIONS"
            return HTTP.Response(200, cors_headers)
        else
            r = handle(req)
            append!(r.headers, allowed_origins)
            return r
        end
    end
end

isnumerical(::Type{<:Number}) = true
isnumerical(::Type{Bool}) = false
isnumerical(::Type) = false

function numerical_summary(x)
    min, max = extrema(x)
    diff = max - min
    step = if eltype(x) <: Integer && diff ≤ 100
        1
    else
        round(diff / 100, sigdigits = 2)
    end
    return (; min, max, step)
end

categorical_summary(x) = unique(x)

function summarize(x)
    return if isnumerical(eltype(x))
        (type = "numerical", summary = numerical_summary(x))
    else
        (type = "categorical", summary = categorical_summary(x))
    end
end

# TODO: compute summaries in DuckDB
@post "/load" function (req::HTTP.Request)
    fs = json(req, DataIngestion.FilesSpec)
    my_exp = Experiment(fs; name = "experiment", prefix = "cache", parent = "data")
    DataIngestion.init!(my_exp)
    table = DBInterface.execute(Tables.columntable, my_exp.repository, "FROM experiment")
    summaries = [merge((; name = string(k)), summarize(v)) for (k, v) in pairs(table)]
    return JSON3.write(summaries)
end

@post "/query" function (req::HTTP.Request)
    query = json(req, DataIngestion.Query)
    table = DBInterface.execute(Tables.columntable, my_exp, query)
    return JSON3.write(table)
end

serve(middleware=[CorsHandler])
