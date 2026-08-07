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

    _register!(router, "POST", "/get-acceptable-paths", HTTP.streamhandler(get_acceptable_paths), settings)
    _register!(router, "POST", "/load-files", HTTP.streamhandler(load_files), settings)
    _register!(router, "POST", "/get-card-widgets", HTTP.streamhandler(get_card_widgets), settings)
    _register!(router, "POST", "/evaluate-pipeline", HTTP.streamhandler(evaluate_pipeline), settings)
    _register!(router, "POST", "/fetch-data", fetch_data, settings)
    _register!(router, "GET", "/get-processed-data", get_processed_data, settings)

    return if async
        HTTP.listen!(router, host, port)
    else
        HTTP.listen(router, host, port)
    end
end
