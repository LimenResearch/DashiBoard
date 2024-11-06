using HTTP: HTTP
using Oxygen: json, @post, serve

using JSON3, DuckDB, Tables

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

const parent_folder = "data"

@post "/load" function (req::HTTP.Request)
    spec = json(req)
    # TODO: folder should depend on session / user
    with_experiment(spec["experiment"]; prefix = "cache", parent = parent_folder) do ex
        DataIngestion.init!(ex, load = true)
        summaries = DataIngestion.summarize(ex.repository, "source")
        return JSON3.write(summaries)
    end
end

@post "/filter" function (req::HTTP.Request)
    spec = json(req)
    with_experiment(spec["experiment"]; prefix = "cache", parent = parent_folder) do ex
        filters = Filters(spec["filters"])
        DataIngestion.select(filters, ex.repository)
        return "Created filtered table"
    end
end

@post "/process" function (req::HTTP.Request)
    spec = json(req)
    with_experiment(spec["experiment"]; prefix = "cache", parent = parent_folder) do ex
        cards = Pipelines.Cards(spec["cards"])
        Pipelines.evaluate(cards, ex.repository, "selection")
        return "Processed filtered table"
    end
end

serve(middleware = [CorsHandler])
