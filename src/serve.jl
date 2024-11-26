const allowed_origins = ["Access-Control-Allow-Origin" => "*"]

const cors_headers = [
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

function launch(; options...)
    @post "/load" function (req::HTTP.Request)
        spec = json(req)
        files = joinpath.("dashiboard", "data", spec["files"])
        DataIngestion.load_files(REPOSITORY[], files)
        summaries = DataIngestion.summarize(REPOSITORY[], "source")
        return JSON3.write(summaries)
    end

    @post "/pipeline" function (req::HTTP.Request)
        spec = json(req)
        filters = Filters(spec["filters"])
        cards = Cards(spec["cards"])
        DataIngestion.select(filters, REPOSITORY[])
        Pipelines.evaluate(cards, REPOSITORY[], "selection")
        summaries = DataIngestion.summarize(REPOSITORY[], "selection")
        return JSON3.write(summaries)
    end

    @post "/fetch" function (req::HTTP.Request)
        spec = json(req)
        table = spec["processed"] ? "selection" : "source"
        io = IOBuffer()
        print(io, "{\"values\": ")
        DBInterface.execute(
            x -> arraytable(io, Tables.columns(x)),
            REPOSITORY[],
            "FROM $table LIMIT ? OFFSET ?;",
            [spec["limit"], spec["offset"]]
        )
        count = DBInterface.execute(
            first,
            REPOSITORY[],
            "SELECT count(*) AS nrows FROM $table;"
        )
        print(io, " , \"length\": ", count.nrows, "}")
        return String(take!(io))
    end

    serve(; middleware = [CorsHandler], options...)
end
