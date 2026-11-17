function run_pipeline(
        repository::Repository, pipeline::Pipeline,
        tbl::AbstractString, id_var::AbstractString;
        schema::Maybe{AbstractString} = nothing,
        train_callback, eval_callback, train::Bool
    )

    if train
        Pipelines.train_evaljoin!(
            repository, pipeline, tbl, id_var;
            schema, train_callback, eval_callback
        )
    else
        Pipelines.evaljoin(
            repository, pipeline, tbl, id_var;
            schema, eval_callback
        )
    end

    return
end

function _execute(
        repository::Repository,
        filters::AbstractVector, pipeline::Pipeline,
        config::Config, flow::DataFlow;
        directory::Maybe{AbstractString} = nothing,
        from_run::Maybe{Run} = nothing, train::Bool
    )

    select_callback = SELECT_CALLBACK[]
    train_callback = TRAIN_CALLBACK[]
    eval_callback = EVAL_CALLBACK[]
    (; id_var, file_based) = flow

    input_cols = union([id_var], Pipelines.get_source_vars(pipeline))
    output_cols = union(Pipelines.get_output_vars(pipeline), [id_var])

    local from::Maybe{Int64}
    if isnothing(from_run)
        from = nothing
    else
        from = from_run._id
        load_nodes!(pipeline.nodes, from_run)
    end

    if flow.file_based
        with_table_name(repository) do tbl
            kwargs = make(Dict{Symbol, Any}, flow.source_options)
            load_filtered(repository, [flow.source], filters, input_cols, tbl; kwargs...)
            select_callback()
            run_pipeline(
                repository, pipeline, tbl, id_var;
                train_callback, eval_callback, train
            )

            if !isempty(flow.destination_options)
                throw(ArgumentError("`destination_options` are not yet supportd"))
            end
            sql, ps = DuckDBUtils.render_params(
                DuckDBUtils.get_catalog(repository),
                From(tbl) |> Select(args = Get.(output_cols))
            )
            DBInterface.execute(
                Returns(nothing), repository,
                "COPY ($(sql)) TO $(to_sql(flow.destination));", ps
            )
        end
    elseif isnothing(flow.database)
        with_table_name(repository) do dst
            with_table_name(repository, virtual = true) do src
                (; source, destination, schema) = flow

                DuckDBUtils.replace_table(
                    repository, "FROM $(in_database(source, schema, flow.database))", src;
                    virtual = true
                )

                DataIngestion.select(
                    repository, filters, src => dst;
                    transform = Select(args = Get.(input_cols))
                )

                select_callback()

                run_pipeline(
                    repository, pipeline, dst, id_var;
                    train_callback, eval_callback, train
                )

                upload_table(
                    repository, dst, output_cols,
                    in_database(destination, schema, flow.database)
                )
            end
        end
    end

    run = Run(; from, trained = train, directory)
    reports = Pipelines.report(repository, pipeline.nodes)
    result = Result(reports)
    entry = Entry(run, config, flow, result)

    return entry, filters, pipeline.nodes
end

function _execute(
        repository::Repository, config::Config, flow::DataFlow; options...
    )
    filters = initialize_filters(config, flow)
    pipeline = initialize_pipeline(config, flow)
    return _execute(repository, filters, pipeline, config, flow; options...)
end

function execute(
        registry::Registry, repository::Repository, args...;
        directory::Maybe{AbstractString} = nothing,
        from::Maybe{Integer} = nothing, train::Bool,
    )

    from_run = get_run(registry, from)
    _entry, _, nodes = _execute(
        repository, args...;
        directory, from_run, train
    )
    entry = set_id(_entry, get_id(registry))
    # TODO: also provide some checkpointing options in case of crash
    train && save_nodes(nodes, entry.run)
    return insert_entry(registry, entry)
end
