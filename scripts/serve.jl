using HTTP: HTTP
using Oxygen: json, @post, serve

using JSON3, DuckDB, Dates, Tables, UUIDs

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

const sessions = DataIngestion.Repository(DuckDB.DB(joinpath("cache", "sessions.duckdb")))

DBInterface.execute(
    Returns(nothing),
    sessions,
    "CREATE OR REPLACE TABLE sessions(name VARCHAR PRIMARY KEY, path VARCHAR, time DATETIME)"
)

@post "/load" function (req::HTTP.Request)
    spec = json(req)
    # TODO: folder should depend on session / user
    path = joinpath("cache", "experiments", string(uuid4()))
    files = joinpath.("data", spec["files"])
    with_experiment(path, files) do ex
        DataIngestion.initialize(ex)
        DBInterface.execute(
            Returns(nothing),
            sessions,
            "INSERT OR REPLACE INTO sessions VALUES (?, ?, ?)",
            [spec["session"], path, now()]
        )
        summaries = DataIngestion.summarize(ex.repository, "source")
        return JSON3.write(summaries)
    end
end

@post "/pipeline" function (req::HTTP.Request)
    spec = json(req)
    sql = "FROM sessions WHERE name = (?)"
    res = DBInterface.execute(first, sessions, sql, [spec["session"]])
    with_experiment(res.path; prefix, parent = parent_folder) do ex
        filters = Filters(spec["filters"])
        cards = Pipelines.Cards(spec["cards"])
        DataIngestion.select(filters, ex.repository)
        Pipelines.evaluate(cards, ex.repository, "selection")
        return "Evaluated pipeline"
    end
end

serve(middleware = [CorsHandler])
