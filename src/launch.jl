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

function acceptable_files(data_directory)
    return Iterators.flatmap(walkdir(data_directory)) do (root, _, files)
        rel_root = relpath(root, data_directory)
        return (normpath(rel_root, file) for file in files if is_supported(file))
    end
end

function launch(data_directory; options...)
    # TODO: clarify `post` vs `get`
    @post "/list" function (req::HTTP.Request)
        files = collect(String, acceptable_files(data_directory))
        return JSON3.write(files)
    end

    @post "/load" function (req::HTTP.Request)
        spec = json(req)
        files = joinpath.(data_directory, spec["files"])
        DataIngestion.load_files(REPOSITORY[], files)
        summaries = DataIngestion.summarize(REPOSITORY[], "source")
        return JSON3.write(summaries)
    end

    @post "/card-configurations" function (req::HTTP.Request)
        spec = json(req) |> Config
        configs = Pipelines.card_configurations(; spec...)
        return JSON3.write(configs)
    end

    @post "/pipeline" function (req::HTTP.Request)
        spec = json(req)
        filters = get_filter.(spec["filters"])
        cards = get_card.(spec["cards"])
        DataIngestion.select(REPOSITORY[], filters)
        Pipelines.evaluate(REPOSITORY[], cards, "selection")
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
