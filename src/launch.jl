const ALLOWED_ORIGINS = ["Access-Control-Allow-Origin" => "*"]

const CORS_HEADERS = [
    ALLOWED_ORIGINS...,
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST",
]

function CorsHandler(handle)
    return function (req::HTTP.Request)
        # return headers on OPTIONS request
        if HTTP.method(req) == "OPTIONS"
            return HTTP.Response(200, CORS_HEADERS)
        else
            r = handle(req)
            append!(r.headers, ALLOWED_ORIGINS)
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

stream_file(stream::IO, path::AbstractString) = open(io -> write(stream, io), path)

stringify_visualization(::Nothing) = nothing
stringify_visualization(x) = sprint(show, MIME"image/svg+xml"(), x)

function launch(
        data_directory;
        host = "127.0.0.1",
        port = 8080,
        async = false,
        training_directory,
        model_directory,
    )

    with_scoped_values(f) = with(
        f,
        Pipelines.PARSER => Pipelines.default_parser(),
        Pipelines.MODEL_DIR => model_directory,
        Pipelines.TRAINING_DIR => training_directory,
    )

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
        spec = json(req) |> to_config
        configs = with_scoped_values(() -> Pipelines.card_configurations(; spec...))
        return JSON3.write(configs)
    end

    @post "/pipeline" function (req::HTTP.Request)
        spec = json(req)
        filters = get_filter.(spec["filters"])
        cards = with_scoped_values(() -> get_card.(spec["cards"]))
        DataIngestion.select(REPOSITORY[], filters)
        nodes = Pipelines.evaluate(REPOSITORY[], cards, "selection")
        vs = Pipelines.visualize(REPOSITORY[], nodes)
        visualization = stringify_visualization.(vs)
        summaries = DataIngestion.summarize(REPOSITORY[], "selection")
        return JSON3.write((; summaries, visualization))
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

    @stream "/processed-data" function (stream::HTTP.Stream)
        mktempdir() do dir
            path = joinpath(dir, "processed-data.csv")
            export_table(REPOSITORY[], path)

            HTTP.setheader(stream, "Content-Type" => "text/csv")
            HTTP.setheader(stream, "Transfer-Encoding" => "chunked")
            HTTP.setheader(stream, "Content-Length" => string(filesize(path)))

            startwrite(stream)
            stream_file(stream, path)
            closewrite(stream)
        end
    end

    serve(; middleware = [CorsHandler], host, port, async)
end
