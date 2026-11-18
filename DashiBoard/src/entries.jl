"""
    @kwarg struct Run
        _id::Int64
        started_at::DateTime = now()
        completed_at::Union{DateTime, Nothing} = nothing
        from::Union{Int64, Nothing}
        trained::Bool
        directory::Union{String, Nothing}
    end

Structure to encode when and how a configuration was run.
It is composed of the following fields.
- `_id`: unique identifier,
- `started_at`: time of run start,
- `completed_at`: time of run end,
- `from`: potential entry from which model weights were loaded,
- `trained`: whether model weights were trained,
- `directory`: directory where model weights were saved.
"""
@kwarg struct Run
    _id::Int64 = 0
    started_at::DateTime = now()
    completed_at::Maybe{DateTime} = nothing
    from::Maybe{Int64}
    trained::Bool
    directory::Maybe{String} # No weight saving needed when evaluating
end

set_id(run::Run, _id::Integer) = Run(; _id, run.started_at, run.completed_at, run.from, run.trained, run.directory)

set_completed_at(run::Run, t::DateTime) = Run(; run._id, run.started_at, t, run.from, run.trained, run.directory)

"""
    struct Config
        filters::Vector{Dict{String, Any}}
        nodes::Vector{Dict{String, Any}}
        groups::Dict{String, Any}
    end

Configuration structure encoding data selection and transformation.

## Examples

```julia
filters = [
    Dict(
        "interval" => Dict("min" => 2011, "max" => 2011),
        "colname" => "year", "type" => "interval"
    ),
    Dict(
        "list" => ["NW", "SE"],
        "colname" => "cbwd", "type" => "list"
    ),
]
cards = [
    Dict(
        "type" => "split",
        "method" => "percentile",
        "method_options" => Dict("percentile" => 0.9),
        "order_by" => ["No"],
        "by" => ["cbwd"],
        "output" => "_percentile_partition"
    ),
    Dict(
        "type" => "rescale",
        "method" => "zscore",
        "by" => ["cbwd"],
        "inputs" => ["PRES", "TEMP"],
        "partition" => "_tiled_partition"
    ),
]
nodes = [Dict("card" => card) for card in cards]
Config(; filters, nodes)
```
"""
@kwarg struct Config
    filters::Vector{StringDict} = StringDict[]
    nodes::Vector{StringDict} = StringDict[]
    groups::StringDict = StringDict()
end

Config(d::AbstractDict) = StructUtils.make(Config, d)

function Base.show(io::IO, ::MIME"text/plain", config::Config)
    printstyled(io, "Config with filters\n", bold = true)
    JSON.json(io, config.filters; jsonlines = true, JSON_OPTIONS...)
    printstyled(io, "nodes\n", bold = true)
    JSON.json(io, config.nodes; jsonlines = true, JSON_OPTIONS...)
    printstyled(io, "and groups\n", bold = true)
    for (grp_key, grp_val) in pairs(config.groups)
        print(io, grp_key, " = ")
        JSON.json(io, grp_val; JSON_OPTIONS...)
        println(io)
    end
    return
end

"""
    struct DataFlow
        id_var::String
        source::String
        destination::String
        schema::Union{String, Nothing}
        database::Union{String, Nothing}
        file_based::Bool = false
        source_options::Dict{String, Any} = Dict{String, Any}()
        destination_options::Dict{String, Any} = Dict{String, Any}()
        source_metadata::Dict{String, Any} = Dict{String, Any}
    end

Encode pipeline data flow, from `source` to `destination` tables within `schema`.
"""
@kwarg struct DataFlow
    id_var::String
    source::String
    destination::String
    schema::Maybe{String} = nothing
    database::Maybe{String} = nothing
    file_based::Bool = false
    source_options::StringDict = StringDict()
    destination_options::StringDict = StringDict()
    # `source_metadata["cols"]` is a list of available column names
    # it is used to validate the pipeline
    source_metadata::StringDict = StringDict()
end

DataFlow(d::AbstractDict) = StructUtils.make(DataFlow, d)

# TODO: use `DataFlow` to validate filters
initialize_filters(c::Config, ::DataFlow) = Filter.(c.filters)

# TODO: include checks from below
function initialize_pipeline(c::Config, flow::DataFlow)
    cols = get(flow.source_metadata, "cols", nothing)
    return isnothing(cols) ? Pipeline(c.nodes, c.groups) : Pipeline(c.nodes, c.groups, cols)
end

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

const FieldType = Union{Run, Config, DataFlow, Result}

"""
    struct Entry
        run::Run
        config::Config
        flow::DataFlow
        result::Result
    end

Structure to encode complete outcome and configuration of a training or evaluation run.
See also:
- [`Run`](@ref),
- [`Config`](@ref),
- [`DataFlow`](@ref),
- [`Result`](@ref).
"""
struct Entry
    run::Run
    config::Config
    flow::DataFlow
    result::Result
end

set_id(e::Entry, _id::Integer) = Entry(set_id(e.run, _id), e.config, e.flow, e.result)

function _execute_pipeline(
        run:: Run, config::Config, flow::DataFlow;
        select_callback = Returns(nothing),
        train_callback = Returns(nothing),
        eval_callback = Returns(nothing)
    )

    train = run.trained
    may_refer = referable(config.nodes, config.groups)
    cols = get(flow.source_metadata, "cols", nothing)

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
    filters = initialize_filters(config, flow)
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
    unfit = model_issues(REPOSITORY[], pipeline, flow.source)
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
        orig = From(flow.source) |> Partition() |> Define(flow.id_var => Agg.row_number())
        DataIngestion.select(REPOSITORY[], filters, orig => flow.destination)
        select_callback()
        # The columns available *to* the pipeline, so the group API can validate references
        # against them rather than accepting a name that does not exist and failing later in SQL.
        return try
            if train
                Pipelines.train_evaljoin!(
                    REPOSITORY[], pipeline, flow.destination, flow.id_var;
                    train_callback, eval_callback
                )
            else
                Pipelines.evaljoin(
                    REPOSITORY[], pipeline, flow.destination, flow.id_var;
                    eval_callback
                )
            end
            report = Pipelines.report(REPOSITORY[], pipeline.nodes)
            vs = Pipelines.visualize(REPOSITORY[], pipeline.nodes)
            visualization = stringify_visualization.(vs)
            graph = sprint(Pipelines.graphviz, pipeline)
            # Recomputed: the pipeline has added its output columns since `available` was taken.
            summaries = DataIngestion.summarize(REPOSITORY[], flow.destination)
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
