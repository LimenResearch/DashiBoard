function get_handlers(
        workspace::AbstractString;
        data_dir::AbstractString = workspace,
        pipeline_dir::AbstractString = workspace,
        filter_dir::AbstractString = workspace,
        model_dir::AbstractString = workspace,
        training_dir::AbstractString = workspace,
        parser::Pipelines.Parser = Pipelines.default_parser(),
        extensions::AbstractDict = Dict{String, Any}(),
        extension_of::AbstractDict = Dict{String, String}()
    )

    handlers, stream_handlers = StringDict(), StringDict()

    handlers["list-files"] = list_files
    handlers["read-document"] = StructuredHandler(read_document, :document)
    handlers["write-document"] = StructuredHandler(write_document, :document)
    handlers["list-configurations"] = list_configurations
    handlers["read-configuration"] = StructuredHandler(read_configuration, :configuration)
    handlers["write-configuration"] = StructuredHandler(write_configuration, :configuration)

    for (name, kind, content, shape) in KIND_ROUTES
        reader, writer = shape === :document ? (read_document, write_document) : (read_configuration, write_configuration)
        handlers["read-$(name)"] = KindHandler(reader, kind, content)
        handlers["write-$(name)"] = KindHandler(writer, kind, content)
    end

    handlers["load-files"] = StructuredHandler(load_files, :load)
    handlers["get-card-ir"] = get_card_ir
    handlers["validate-card"] = StructuredHandler(validate_card, :pipeline)
    handlers["evaluate-pipeline"] = evaluate_pipeline

    stream_handlers["bundle-pipeline"] = StructuredHandler(bundle_pipeline, :bundle)
    stream_handlers["fetch-data"] = fetch_data
    stream_handlers["get-processed-data"] = get_processed_data

    middleware = DashiBase.ScopedMiddleware(
        Pipelines.PARSER => parser,
        Pipelines.MODEL_DIR => model_dir,
        Pipelines.TRAINING_DIR => training_dir,
        DataIngestion.DATA_DIR => data_dir,
        WORKSPACE => workspace,
        PIPELINE_DIR => pipeline_dir,
        FILTER_DIR => filter_dir,
        EXTENSIONS => extensions,
        EXTENSION_OF => extension_of,
    )

    map!(middleware, values(handlers))
    map!(middleware, values(stream_handlers))

    probe_handlers = copy(handlers)
    map!(DashiBase.probe_middleware, values(probe_handlers))

    return handlers, stream_handlers, probe_handlers
end

"""
    launch(workspace; host, port, async, data_dir, pipeline_dir, filter_dir, model_dir, training_dir, parser)

Serve DashiBoard for `workspace`, the directory every file route is confined to.

Five directories say where each kind of file is: `data_dir` the tables, `pipeline_dir` and
`filter_dir` the documents, `model_dir` and `training_dir` the configurations. Each defaults to
the workspace itself, which is a flat folder with everything in it; `bin/launch.jl` is where the
layout, a `dashiboard.toml` and the flags turn into these keywords. `extensions` and
`extension_of` are what the launcher learned registering extensions, for a download to name
them.
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

    handlers, stream_handlers, probe_handlers = get_handlers(
        workspace;
        data_dir, pipeline_dir, filter_dir, model_dir, training_dir,
        parser, extensions, extension_of,
    )

    router = HTTP.Router(
        HTTP.streamhandler(cors404),
        HTTP.streamhandler(cors405)
    )

    HTTP.register!(router, "POST", "/rpc", JSONHandler(handlers))
    HTTP.register!(router, "POST", "/rpc-probe", JSONHandler(probe_handlers))
    stream_handler = JSONStreamHandler(stream_handlers)
    HTTP.register!(router, "POST", "/rpc-stream", stream_handler)
    # The table download as a plain GET: a link cannot carry a JSON-RPC body, and only a download
    # the browser makes itself streams to disk rather than through the page's memory.
    HTTP.register!(router, "GET", "/get-processed-data", stream -> stream_response(stream_handler, stream, PROCESSED_DATA_REQUEST))

    cors_router = router |> CorsMiddleware

    # Said out loud, so whoever launched from a terminal knows the warm-up is over.
    @info "DashiBoard is listening" url = "http://$(host):$(port)" workspace data_dir pipeline_dir filter_dir model_dir training_dir environment = Base.active_project()
    return async ? HTTP.listen!(cors_router, host, port) : HTTP.listen(cors_router, host, port)
end
