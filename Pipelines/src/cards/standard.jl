# StandardCard interface:
# - `_train(c, tbl, id; weights) -> model`
# - `(c)(model, tbl, id) -> new_tbl, new_id`

# Implementation of Card methods

function train(
        repository::Repository, c::StandardCard,
        source::AbstractString, id_var::AbstractPrimaryKey;
        schema::Maybe{AbstractString} = nothing
    )

    vars = SourceVariables(c)
    sel = (vars.group_by, vars.helpers, vars.inputs, vars.targets, to_stringlist(vars.weights))
    q = From(source) |>
        filter_training(vars.partition) |>
        sort_columns(vars.order_by) |>
        select_columns([id_var], sel...)

    t = DBInterface.execute(fromtable, repository, q; schema)
    model = _train(c, t, id_var)
    return model
end

function (c::StandardCard)(model, state, t, id_var)
    table = c(model, t, id_var)
    return table, state
end

function evaluate(
        repository::Repository,
        c::StandardCard,
        model,
        state,
        (source, destination)::Pair,
        id_var::AbstractPrimaryKey;
        schema::Maybe{AbstractString} = nothing
    )

    vars = SourceVariables(c)

    q = From(source) |>
        sort_columns(vars.order_by) |>
        select_columns([id_var], vars.group_by, vars.helpers, vars.inputs)
    t = DBInterface.execute(fromtable, repository, q; schema)

    table, state′ = c(model, state, t, id_var)
    load_table(repository, table, destination; schema)
    colnames = Iterators.map(string, Tables.columnnames(Tables.columns(table)))
    output_cols = collect(String, Iterators.filter(!=(id_var), colnames))
    return output_cols, state′
end
