const SELECT_CALLBACK = ScopedValue{Any}(Returns(nothing))
const TRAIN_CALLBACK = ScopedValue{Any}(Returns(nothing))
const EVAL_CALLBACK = ScopedValue{Any}(Returns(nothing))

abstract type ValidatedCallable end

# simple case: `x` is a callable and already validated struct
validate_method(x::ValidatedCallable) = x

validate_method(::Type{T}, spec::AbstractDict) where {T} = validate_method(T(x))

@kwarg struct FilesConfig
    files::Vector{String}
end

FilesConfig(spec::AbstractDict) = StructUtils.make(FilesConfig, spec)

@kwarg struct TableConfig
    id_var::String
    table::String
    schema::Maybe{String} = nothing
end

TableConfig(spec::AbstractDict) = StructUtils.make(TableConfig, spec)

@kwarg struct LoadFiles <: ValidatedCallable
    files::FilesConfig
    table::TableConfig
end

LoadFiles(spec::AbstractDict) = StructUtils.make(LoadFiles, spec)

function ((; files, table)::LoadFiles)()
    DataIngestion.load_files(REPOSITORY[], files.files, table.table; table.schema, table.id_var)
    return DataIngestion.summarize(REPOSITORY[], table.table; table.schema)
end

@kwarg struct SelectionConfig
    filters::Vector{Filter}
    cols::Maybe{Vector{String}} = nothing
end

SelectionConfig(spec::AbstractDict) = StructUtils.make(SelectionConfig, spec)

@kwarg struct SelectData <: ValidatedCallable
    source::TableConfig
    destination::TableConfig
    selection::SelectionConfig
end

SelectData(spec::AbstractDict) = StructUtils.make(SelectData, spec)

function ((; source, destination, selection)::SelectData)()
    (; table, schema) = destination
    virtual = true
    # work-around in case source and destination belong to different schemas
    DuckDBUtils.with_table_name(REPOSITORY[]; schema, virtual) do src
        DuckDBUtils.replace_table(
            REPOSITORY[],
            "FROM $(DuckDBUtils.in_schema(source.table, source.schema))", src;
            schema, virtual
        )
        transform = isnothing(selection.cols) ? identity : Select(args = Get.(selection.cols))
        DataIngestion.select(
            REPOSITORY[], selection.filters, src => table; schema, transform
        )
    end
    return
end

@kwarg struct PipelineConfig
    nodes::Vector{StringDict} = StringDict[]
    groups::StringDict = StringDict()
end

PipelineConfig(spec::AbstractDict) = StructUtils.make(PipelineConfig, spec)

"""
    struct Result
        summaries::Vector{VariableSummary}
        visualization::String
        graph::String
        report::Vector{StringDict}
    end

Structure to encode outcome of training or evaluation run.
"""
@kwarg struct Result
    report::Vector{StringDict}
    visualization::Vector{Maybe{String}}
    summaries::Vector{VariableSummary}
    graph::String
end

@kwarg struct RunPipeline
    table::TableConfig
    proxy::TableConfig = table
    pipeline::PipelineConfig
    train::Bool
end

RunPipeline(spec::AbstractDict) = StructUtils.make(RunPipeline, spec)

function validate_method(rp::RunPipeline)
    table, proxy, config, train = rp.table, rp.proxy, rp.pipeline, rp.train
    may_refer = referable(config.nodes, config.groups)
    cols = DuckDBUtils.colnames(REPOSITORY[], proxy.table; proxy.schema)

    # Before building: see `empty_group_issues` for why construction cannot report this itself.
    # The cards' own schema failures go out in the same answer (`card_schema_issues`), groups
    # first as in the document.
    empty = empty_group_issues(config.groups)
    if !isempty(empty)
        issues = vcat(empty, card_schema_issues(config.nodes, config.groups, cols))
        failure = (;
            kind = "pipeline", cols,
            errors = [issue.message for issue in issues], issues, referable = may_refer,
        )
        throw(DashiBase.StructuredException(StructUtils.make(StringDict, failure)))
    end

    # Running is the one step nothing static can vet. The probe answers everything that can be
    # known from the document alone, so what reaches here is a fault of the *data* — PCA asked for
    # more components than there are columns, a model that will not converge — and it surfaces only
    # by being run.
    pipeline = try
        Pipelines.Pipeline(config.nodes, config.groups, cols)
    catch exception
        exception isa Exception || rethrow()
        # Always `pipeline`: this route resolves and never runs, so a fault it can see is by
        # construction a fault of the document. Deliberately not logged — the probe fires on every
        # edit, and most edits are documents the author has not finished writing yet.
        failure = (; build_failure(config.nodes, config.groups, exception)..., cols, referable = may_refer)
        throw(DashiBase.StructuredException(StructUtils.make(StringDict, failure)))
    end
    # Sent with every answer below, so a picker offers an item only what cannot make a loop.

    absent = Dict(Pipelines.unproduced_references(pipeline, cols))
    # Sized from the loaded table; what earlier cards add is not in it yet and counts as one column.
    unfit = model_issues(REPOSITORY[], pipeline, proxy.table; proxy.schema)
    # `Pipelines.get_id` is the naming rule everything else uses; inventing an index here made
    # this the third answer to "what is this node called" in three files.
    ids = Pipelines.get_id.(config.nodes)

    # The second source of pointed failures. An unproduced reference is addressed at *node*
    # granularity, not at the selector item that named it: resolution returns the column list and
    # keeps no provenance back to the item, so `{cols = "PRES", through = [...]}` cannot be
    # singled out from its siblings. Reported in the same shape as a schema failure so a form
    # iterates one list, with `reason` telling them apart.
    unproduced_issues = [
        (;
            pointer = "/nodes/$(i - 1)/card",
            reason = "unproduced",
            # an error: nothing produces the column, so the document cannot run
            severity = "error",
            found = nothing,
            allowed = nothing,
            missing = names,
            related = String[],
            message = "nothing produces " * join(names, ", "),
        )
            for (i, names) in sort!(collect(absent), by = first)
    ]
    nodes = map(enumerate(pipeline.nodes)) do (i, node)
        return (;
            id = ids[i],
            inputs = Pipelines.get_node_inputs(node),
            outputs = Pipelines.get_node_outputs(node),
            unproduced = get(absent, i, String[]),
            # What a `through` chain may do with this node, so a picker offers only chains the
            # pipeline would accept rather than guessing from which columns the node reads.
            through = Pipelines.through_options(node),
            # What a selection may narrow this node to: each named product with its columns.
            products = Pipelines.product_outputs(node),
            # What the card's lists resolved to, where a form has to spell them out — one row
            # per column to choose a transform for, say. Empty for most cards.
            lists = Pipelines.resolved_lists(Pipelines.get_card(node)),
        )
    end

    # Errors first, then warnings: a client reading the list top-down sees what blocks the run
    # before what merely deserves a look.
    issues = vcat(unproduced_issues, unfit, overwrite_warnings(pipeline, cols))
    probe = (;
        cols,
        nodes,
        referable = may_refer,
        source_vars = Pipelines.get_source_vars(pipeline),
        output_vars = Pipelines.get_output_vars(pipeline),
        errors = String[],
        issues,
    )
    # A reference nothing produces, or a model that cannot be built, is a fault of the document
    # found by resolving rather than by running: the document is refused, with everything the
    # probe found, so a form marks the nodes as it does for any other refusal.
    if !isempty(absent) || !isempty(unfit)
        errors = [issue.message for issue in issues if issue.severity == "error"]
        failure = (; probe..., kind = "pipeline", errors)
        throw(DashiBase.StructuredException(StructUtils.make(StringDict, failure)))
    end

    return ProbedThunk(probe) do
        return try
            if train
                Pipelines.train_evaljoin!(
                    REPOSITORY[], pipeline, table.table, table.id_var;
                    train_callback = TRAIN_CALLBACK[], eval_callback = EVAL_CALLBACK[], table.schema
                )
            else
                Pipelines.evaljoin(
                    REPOSITORY[], pipeline, table.table, table.id_var;
                    eval_callback = EVAL_CALLBACK[], table.schema
                )
            end
            # FIXME: this signature should include table, schema and id_var
            report = Pipelines.report(REPOSITORY[], pipeline.nodes)
            vs = Pipelines.visualize(REPOSITORY[], pipeline.nodes)
            visualization = stringify_visualization.(vs)
            graph = sprint(Pipelines.graphviz, pipeline)
            # Recomputed: the pipeline has added its output columns since `available` was taken.
            summaries = DataIngestion.summarize(REPOSITORY[], table.table; table.schema)
            Result(; report, visualization, summaries, graph)
        catch exception
            exception isa Exception || rethrow()
            # Logged, unlike the probe's: this one was asked for deliberately, and an operator wants
            # the backtrace whether the cause was the data or a bug of ours.
            handler = train ? "train-evaluate-pipeline" : "evaluate-pipeline"
            @error "$(handler): the run failed" exception = (exception, catch_backtrace())
            failure = failure_report(:execution, exception)
            throw(DashiBase.StructuredException(StructUtils.make(StringDict, failure)))
        end
    end
end

@kwarg struct ExportData <: ValidatedCallable
    table::TableConfig
    destination::String
    format::String
    cols::Maybe{Vector{String}} = nothing
end

function ((; table, destination, format, cols)::ExportData)()
    q = isnothing(cols) ? From(table.table) : From(table.table) |> Select(args = Get.(cols))
    return export_table(REPOSITORY[], q, destination; format, table.schema, use_tmp_file = false)
end
