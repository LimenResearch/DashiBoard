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

    router = HTTP.Router()

    function list_handler(::HTTP.Request)
        files = collect(String, acceptable_files(data_directory))
        return JSON3.write(files)
    end
    HTTP.register!(router, "POST", "/list", request_middleware(list_handler))

    function load_handler(req::HTTP.Request)
        spec = JSON3.read(req.body)
        files = joinpath.(data_directory, spec["files"])
        DataIngestion.load_files(REPOSITORY[], files)
        summaries = DataIngestion.summarize(REPOSITORY[], "source")
        return JSON3.write(summaries)
    end
    HTTP.register!(router, "POST", "/load", request_middleware(load_handler))

    function card_configurations_handler(req::HTTP.Request)
        spec = JSON3.read(req.body) |> to_config
        configs = with_scoped_values(() -> Pipelines.card_configurations(; spec...))
        return JSON3.write(configs)
    end
    HTTP.register!(router, "POST", "/card-configurations", request_middleware(card_configurations_handler))

    function pipeline_handler(req::HTTP.Request)
        spec = JSON3.read(req.body)
        filters = get_filter.(spec["filters"])
        cards = with_scoped_values(() -> get_card.(spec["cards"]))
        DataIngestion.select(REPOSITORY[], filters)
        nodes = Pipelines.evaluate(REPOSITORY[], cards, "selection")
        report = Pipelines.report(REPOSITORY[], nodes)
        vs = Pipelines.visualize(REPOSITORY[], nodes)
        visualization = stringify_visualization.(vs)
        summaries = DataIngestion.summarize(REPOSITORY[], "selection")
        return JSON3.write((; summaries, visualization, report))
    end
    HTTP.register!(router, "POST", "/pipeline", request_middleware(pipeline_handler))

    function fetch_handler(req::HTTP.Request)
        spec = JSON3.read(req.body)
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
    HTTP.register!(router, "POST", "/fetch", request_middleware(fetch_handler))

    function processed_data_handler(stream::HTTP.Stream)
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
    HTTP.register!(router, "GET", "/processed-data", stream_middleware(processed_data_handler))

    return if async
        HTTP.serve!(router, host, port, stream = true)
    else
        HTTP.serve(router, host, port, stream = true)
    end
end
