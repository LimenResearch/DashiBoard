using HTTP: HTTP
using Oxygen: json, @post, serve
using ConcurrentUtilities: lock, Lockable

using JSON3, DuckDB, Tables

using DataIngestion

allowed_origins = ["Access-Control-Allow-Origin" => "*"]

cors_headers = [
    allowed_origins...,
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST",
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

const LOCK = ReentrantLock()
struct WithSession{T}
    session::String
    value::T
end

mutable struct SessionData
    experiment::Experiment
    query::Union{DataIngestion.Query, Nothing}
end

const QUERIES = Lockable(Dict{String, SessionData}())

struct ExperimentSpec
    name::String
    paths::Vector{Vector{String}}
    format::String
end

function DataIngestion.Experiment(
        spec::ExperimentSpec;
        prefix::AbstractString,
        parent::AbstractString,
    )

    localpaths = map(joinpath, spec.paths)
    files = joinpath.(parent, localpaths)
    return Experiment(; prefix, spec.name, files, spec.format)
end

@post "/load" function (req::HTTP.Request)
    spec = json(req, ExperimentSpec)
    my_exp = Experiment(spec; prefix = "cache", parent = "data")
    DataIngestion.init!(my_exp)
    summaries = DataIngestion.summarize(my_exp.repository, "experiment")
    return JSON3.write(summaries)
end

# FIXME: update

@post "/query" function (req::HTTP.Request)
    query = json(req, DataIngestion.Query)
    table = DBInterface.execute(Tables.columntable, my_exp, query)
    return JSON3.write(table)
end

serve(middleware = [CorsHandler])
