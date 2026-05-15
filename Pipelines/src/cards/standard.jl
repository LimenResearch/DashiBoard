# StandardCard interface:
# - `_train(c, tbl, id; weights) -> model`
# - `(c)(model, tbl, id) -> new_tbl, new_id`

# Implementation of Card methods

function train(
        repository::Repository, c::StandardCard,
        source::AbstractString, id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )

    vars = Variables(c)
    sel = (vars.grouping, vars.helpers, vars.inputs, vars.targets, to_stringlist(vars.weights))
    q = From(source) |>
        filter_training(vars.partition) |>
        sort_columns(vars.sorting) |>
        select_columns([id_var], sel...)

    t = DBInterface.execute(fromtable, repository, q; schema)
    model = _train(c, t, id_var)
    return CardState(content = jldserialize(model))
end

function evaluate(
        repository::Repository,
        c::StandardCard,
        state::CardState,
        (source, destination)::Pair,
        id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )

    vars = Variables(c)

    q = From(source) |>
        sort_columns(vars.sorting) |>
        select_columns([id_var], vars.grouping, vars.helpers, vars.inputs)
    t = DBInterface.execute(fromtable, repository, q; schema)

    model = jlddeserialize(state.content)
    pred_table = c(model, t, id_var)
    load_table(repository, pred_table, destination; schema)
    cols = String[string(k) for k in Tables.columnnames(Tables.columns(pred_table))]
    return setdiff(cols, [id_var])
end
