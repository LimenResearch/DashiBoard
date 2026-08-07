function launch(
        data_directory::AbstractString;
        host::AbstractString = "127.0.0.1",
        port::Integer = 8080,
        async::Bool = false,
        training_directory::AbstractString,
        model_directory::AbstractString,
        parser::Pipelines.Parser = Pipelines.default_parser()
    )

    router = HTTP.Router(
        HTTP.streamhandler(cors404),
        HTTP.streamhandler(cors405)
    )

    HTTP.register!(router, "POST", "/get-acceptable-paths", HTTP.streamhandler(get_acceptable_paths))
    HTTP.register!(router, "POST", "/load-files", HTTP.streamhandler(load_files))
    HTTP.register!(router, "POST", "/get-card-widgets", HTTP.streamhandler(get_card_widgets))
    HTTP.register!(router, "POST", "/evaluate-pipeline", HTTP.streamhandler(evaluate_pipeline))
    HTTP.register!(router, "POST", "/fetch-data", fetch_data)
    HTTP.register!(router, "GET", "/get-processed-data", get_processed_data)

    cors_router = router |> CorsMiddleware

    return @with(
        Pipelines.PARSER => parser,
        Pipelines.MODEL_DIR => model_directory,
        Pipelines.TRAINING_DIR => training_directory,
        DataIngestion.DATA_DIR => data_directory,
        async ? HTTP.listen!(cors_router, host, port) : HTTP.listen(cors_router, host, port)
    )
end
