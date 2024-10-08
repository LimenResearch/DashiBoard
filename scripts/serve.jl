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

isnumeric(::Type{<:Number}) = true
isnumeric(::Type{Bool}) = false
isnumeric(::Type) = false

function numeric_summary(x)
    min, max = extrema(x)
    return (; min, max)
end

categorical_summary(x) = unique(x)

function summarize(x)
    return if isnumeric(eltype(x))
        (type = "numeric", summary = numeric_summary(x))
    else
        (type = "categorical", summary = categorical_summary(x))
    end
end

@post "/load" function (req::HTTP.Request)
    fs = json(req, DataIngestion.FilesSpec)
    my_exp = Experiment(fs; name = "experiment", prefix = "cache", parent = "data")
    DataIngestion.init!(my_exp)
    table = DBInterface.execute(Tables.columntable, my_exp.repository, "FROM experiment")
    return JSON3.write(map(summarize, table))
end

@post "/query" function (req::HTTP.Request)
    query = json(req, DataIngestion.Query)
    table = DBInterface.execute(Tables.columntable, my_exp, query)
    return JSON3.write(table)
end

serve(middleware=[CorsHandler])
