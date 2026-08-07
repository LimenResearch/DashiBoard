function launch(
        data_directory::AbstractString;
        host = "127.0.0.1",
        port = 8080,
        async = false,
        training_directory::AbstractString,
        model_directory::AbstractString,
        parser::Pipelines.Parser = Pipelines.default_parser()
    )

    router = HTTP.Router(
        HTTP.streamhandler(cors404),
        HTTP.streamhandler(cors405),
        CorsMiddleware
    )

    HTTP.register!(router, "/get-acceptable-paths", HTTP.streamhandler(get_acceptable_paths))
    HTTP.register!(router, "/load-files", HTTP.streamhandler(load_files))
    HTTP.register!(router, "/get-card-widgets", HTTP.streamhandler(get_card_widgets))
    HTTP.register!(router, "/evaluate-pipeline", HTTP.streamhandler(evaluate_pipeline))
    HTTP.register!(router, "/fetch-data", fetch_data)
    HTTP.register!(router, "/get-processed-data", get_processed_data)

    return @with(
        Pipelines.PARSER => parser,
        Pipelines.MODEL_DIR => model_directory,
        Pipelines.TRAINING_DIR => training_directory,
        DataIngestion.DATA_DIR => data_directory,
        async ? HTTP.listen!(router, host, port) : HTTP.listen(router, host, port)
    )
end
