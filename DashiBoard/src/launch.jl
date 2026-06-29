stringify_visualization(::Nothing) = nothing
stringify_visualization(x) = sprint(show, MIME"image/svg+xml"(), x)

stream_file(stream::HTTP.Stream, path::AbstractString) = open(Fix1(write, stream), path)

# TODO: consider reading / writing directly from the stream

function json_read(stream::HTTP.Stream)
    return JSON.parse(read(stream, String))
end

function json_write(stream::HTTP.Stream, data)
    str = JSON.json(data)
    HTTP.setheader(stream, "Content-Type" => "application/json")
    HTTP.setheader(stream, "Content-Length" => string(sizeof(str)))
    startwrite(stream)
    write(stream, str)
    closewrite(stream)
    HTTP.closeread(stream)
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
        HTTP.listen!(router, host, port)
    else
        HTTP.listen(router, host, port)
    end
end
