stringify_visualization(::Nothing) = nothing
stringify_visualization(x) = sprint(show, MIME"image/svg+xml"(), x)

stream_file(stream::HTTP.Stream, path::AbstractString) = open(Fix1(write, stream), path)

# TODO: consider reading / writing directly from the stream

json_read(stream::HTTP.Stream) = JSON.parse(read(stream, String))

function json_write(stream::HTTP.Stream, data)
    HTTP.setheader(stream, "Content-Type" => "application/json")
    startwrite(stream)
    write(stream, JSON.json(data))
    return
end

function launch(
        data_directory;
        host = "127.0.0.1",
        port = 8080,
        async = false,
        training_directory,
        model_directory,
        parser = Pipelines.default_parser()
    )

    settings = Settings(; parser, model_directory, training_directory, data_directory)

    router = HTTP.Router(
        HTTP.streamhandler(cors404),
        HTTP.streamhandler(cors405),
    )

    _register!(router, "POST", "/get-acceptable-paths", get_acceptable_paths, settings)
    _register!(router, "POST", "/load-files", load_files, settings)
    _register!(router, "POST", "/get-card-widgets", get_card_widgets, settings)
    _register!(router, "POST", "/evaluate-pipeline", evaluate_pipeline, settings)
    _register!(router, "POST", "/fetch-data", fetch_data, settings)
    _register!(router, "GET", "/get-processed-data", get_processed_data, settings)

    return if async
        HTTP.serve!(router, host, port, stream = true)
    else
        HTTP.serve(router, host, port, stream = true)
    end
end
