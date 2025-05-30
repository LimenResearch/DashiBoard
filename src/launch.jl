function acceptable_files(data_directory)
    return Iterators.flatmap(walkdir(data_directory)) do (root, _, files)
        rel_root = relpath(root, data_directory)
        return (normpath(rel_root, file) for file in files if is_supported(file))
    end
end

stringify_visualization(::Nothing) = nothing
stringify_visualization(x) = sprint(show, MIME"image/svg+xml"(), x)

stream_file(stream::HTTP.Stream, path::AbstractString) = open(io -> write(stream, io), path)

json_read(stream::HTTP.Stream) = JSON3.read(stream)

function json_write(stream::HTTP.Stream, data)
    HTTP.setheader(stream, "Content-Type" => "application/json")
    startwrite(stream)
    JSON3.write(stream, data)
    return
end

# JSON utils

# TODO: consider using some JSON setting for this

function jsonify(x::Real)
    isinf(x) && return x > 0 ? "Inf" : "-Inf"
    isnan(x) && return "NaN"
    return x
end

jsonify(x) = x
jsonify(d::AbstractDict) = Dict{String, Any}(string(k) => jsonify(v) for (k, v) in pairs(d))
jsonify(v::AbstractVector) = map(jsonify, v)

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

    router = HTTP.Router(
        HTTP.streamhandler(cors404),
        HTTP.streamhandler(cors405),
    )

    function list_handler(stream::HTTP.Stream)
        _ = json_read(stream)
        files = collect(String, acceptable_files(data_directory))
        json_write(stream, files)
        return
    end
    register_handler!(router, "POST", "/list", list_handler)

    function load_handler(stream::HTTP.Stream)
        spec = json_read(stream)
        files = joinpath.(data_directory, spec["files"])
        DataIngestion.load_files(REPOSITORY[], files)
        summaries = DataIngestion.summarize(REPOSITORY[], "source")
        json_write(stream, summaries)
        return
    end
    register_handler!(router, "POST", "/load", load_handler)

    function card_configurations_handler(stream::HTTP.Stream)
        spec = json_read(stream) |> to_config
        configs = with_scoped_values(() -> Pipelines.card_configurations(; spec...))
        json_write(stream, configs)
        return
    end
    register_handler!(router, "POST", "/card-configurations", card_configurations_handler)

    function pipeline_handler(stream::HTTP.Stream)
        spec = json_read(stream)
        filters = get_filter.(spec["filters"])
        cards = with_scoped_values(() -> get_card.(spec["cards"]))
        DataIngestion.select(REPOSITORY[], filters)
        nodes = Pipelines.evaluate(REPOSITORY[], cards, "selection")
        report = Pipelines.report(REPOSITORY[], nodes) |> jsonify
        vs = Pipelines.visualize(REPOSITORY[], nodes)
        visualization = stringify_visualization.(vs)
        summaries = DataIngestion.summarize(REPOSITORY[], "selection")
        json_write(stream, (; summaries, visualization, report))
        return
    end
    register_handler!(router, "POST", "/pipeline", pipeline_handler)

    function fetch_handler(stream::HTTP.Stream)
        spec = json_read(stream)
        table = spec["processed"] ? "selection" : "source"
        limit::Int, offset::Int = spec["limit"], spec["offset"]

        mktempdir() do dir
            path = joinpath(dir, "data.json")
            DBInterface.execute(
                Returns(nothing),
                REPOSITORY[],
                """
                COPY (FROM "$table" LIMIT \$limit OFFSET \$offset)
                TO '$path' (FORMAT json, ARRAY true);
                """,
                (; limit, offset)
            )
            nrows = DBInterface.execute(
                x -> only(x).count,
                REPOSITORY[],
                """
                SELECT count(*) AS "count" FROM "$table";
                """
            )

            HTTP.setheader(stream, "Content-Type" => "application/json")
            startwrite(stream)

            print(stream, "{\"values\": ")
            stream_file(stream, path)
            print(stream, " , \"length\": ", nrows, "}")
        end
        return
    end
    register_handler!(router, "POST", "/fetch", fetch_handler)

    function processed_data_handler(stream::HTTP.Stream)
        mktempdir() do dir
            path = joinpath(dir, "processed-data.csv")
            export_table(REPOSITORY[], path)

            HTTP.setheader(stream, "Content-Type" => "text/csv")
            HTTP.setheader(stream, "Transfer-Encoding" => "chunked")
            HTTP.setheader(stream, "Content-Length" => string(filesize(path)))

            startwrite(stream)
            stream_file(stream, path)
        end
        return
    end
    register_handler!(router, "GET", "/processed-data", processed_data_handler)

    return if async
        HTTP.serve!(router, host, port, stream = true)
    else
        HTTP.serve(router, host, port, stream = true)
    end
end
