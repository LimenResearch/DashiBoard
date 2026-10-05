"""
    launch(workspace; host, port, async, data_dir, pipeline_dir, filter_dir, model_dir, training_dir, parser)

Serve DashiBoard for `workspace`, the directory every file route is confined to.

Five directories say where each kind of file is: `data_dir` the tables, `pipeline_dir` and
`filter_dir` the documents, `model_dir` and `training_dir` the configurations. `extensions` and
`extension_of` are what the launcher learned registering extensions, for a download to name them. Each defaults to
the workspace itself, which is a flat folder with everything in it; `bin/launch.jl` is where the
layout, a `dashiboard.toml` and the flags turn into these keywords.
"""
function launch(
        workspace::AbstractString;
        host::AbstractString = "127.0.0.1",
        port::Integer = 8080,
        async::Bool = false,
        data_dir::AbstractString = workspace,
        pipeline_dir::AbstractString = workspace,
        filter_dir::AbstractString = workspace,
        model_dir::AbstractString = workspace,
        training_dir::AbstractString = workspace,
        parser::Pipelines.Parser = Pipelines.default_parser(),
        extensions::AbstractDict = Dict{String, Any}(),
        extension_of::AbstractDict = Dict{String, String}()
    )

    router = HTTP.Router(
        HTTP.streamhandler(cors404),
        HTTP.streamhandler(cors405)
    )

    HTTP.register!(router, "POST", "/list-files", HTTP.streamhandler(list_files))
    HTTP.register!(router, "POST", "/read-document", HTTP.streamhandler(read_document))
    HTTP.register!(router, "POST", "/write-document", HTTP.streamhandler(write_document))
    HTTP.register!(router, "POST", "/list-configurations", HTTP.streamhandler(list_configurations))
    HTTP.register!(router, "POST", "/bundle-pipeline", HTTP.streamhandler(bundle_pipeline))
    HTTP.register!(router, "POST", "/read-configuration", HTTP.streamhandler(read_configuration))
    HTTP.register!(router, "POST", "/write-configuration", HTTP.streamhandler(write_configuration))
    for (name, kind, content, shape) in KIND_ROUTES
        reader, writer = shape === :document ? (read_document, write_document) : (read_configuration, write_configuration)
        HTTP.register!(router, "POST", "/read-$(name)", HTTP.streamhandler(kind_handler(reader, kind, content)))
        HTTP.register!(router, "POST", "/write-$(name)", HTTP.streamhandler(kind_handler(writer, kind, content)))
    end
    HTTP.register!(router, "POST", "/load-files", HTTP.streamhandler(load_files))
    HTTP.register!(router, "POST", "/get-card-ir", HTTP.streamhandler(get_card_ir))
    HTTP.register!(router, "POST", "/validate-card", HTTP.streamhandler(validate_card))
    HTTP.register!(router, "POST", "/probe-pipeline", HTTP.streamhandler(probe_pipeline))
    HTTP.register!(router, "POST", "/evaluate-pipeline", HTTP.streamhandler(evaluate_pipeline))
    HTTP.register!(router, "POST", "/fetch-data", fetch_data)
    HTTP.register!(router, "GET", "/get-processed-data", get_processed_data)

    # Logging outermost, so it sees what the CORS layer answers itself (an `OPTIONS` preflight)
    # and what the router rejects before any handler runs (a 404 or 405).
    cors_router = router |> CorsMiddleware |> LoggingMiddleware

    return @with(
        Pipelines.PARSER => parser,
        Pipelines.MODEL_DIR => model_dir,
        Pipelines.TRAINING_DIR => training_dir,
        DataIngestion.DATA_DIR => data_dir,
        WORKSPACE => workspace,
        PIPELINE_DIR => pipeline_dir,
        FILTER_DIR => filter_dir,
        EXTENSIONS => extensions,
        EXTENSION_OF => extension_of,
        begin
            # Said out loud, so whoever launched from a terminal knows the warm-up is over.
            @info "DashiBoard is listening" url = "http://$(host):$(port)" workspace
            async ? HTTP.listen!(cors_router, host, port) : HTTP.listen(cors_router, host, port)
        end
    )
end
