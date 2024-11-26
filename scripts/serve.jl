using HTTP: HTTP
using Oxygen: json, @post, serve
using Scratch: @get_scratch!

using JSON3, JSONTables, DuckDB, Dates, Tables, UUIDs

using DataIngestion, Pipelines

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

const repo = Repository(joinpath(@get_scratch!("cache"), "db.duckdb"))
# TODO: update code below

@post "/load" function (req::HTTP.Request)
    spec = json(req)
    files = joinpath.("data", spec["files"])
    DataIngestion.load_files(repo, files)
    summaries = DataIngestion.summarize(repo, "source")
    return JSON3.write(summaries)
end

@post "/pipeline" function (req::HTTP.Request)
    spec = json(req)
    filters = Filters(spec["filters"])
    cards = Cards(spec["cards"])
    DataIngestion.select(filters, repo)
    Pipelines.evaluate(cards, repo, "selection")
    summaries = DataIngestion.summarize(repo, "selection")
    return JSON3.write(summaries)
end

@post "/fetch" function (req::HTTP.Request)
    spec = json(req)
    table = spec["processed"] ? "selection" : "source"
    io = IOBuffer()
    print(io, "{\"values\": ")
    DBInterface.execute(
        x -> arraytable(io, Tables.columns(x)),
        repo,
        "FROM $table LIMIT ? OFFSET ?;",
        [spec["limit"], spec["offset"]]
    )
    count = DBInterface.execute(first, repo, "SELECT count(*) AS nrows FROM $table;")
    print(io, " , \"length\": ", count.nrows, "}")
    return String(take!(io))
end

serve(middleware = [CorsHandler])
