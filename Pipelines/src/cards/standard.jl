# StandardCard interface:
# - `_train(c, tbl, id; weights) -> model`
# - `(c)(model, tbl, id) -> new_tbl`
#
# A card whose evaluation also rolls its state forward returns
# `(new_tbl, state)`; `evaluate` then returns `(columns, state)` and the node
# stores it (see `_persist_state!` in node.jl). Everything else is untouched.

_with_state(prediction) = (prediction, nothing)
_with_state((prediction, state)::Tuple{SimpleTable, CardState}) = (prediction, state)

# Implementation of Card methods

function train(
        repository::Repository, c::StandardCard,
        source::AbstractString, id_var::AbstractPrimaryKey;
        schema::Union{AbstractString, Nothing} = nothing
    )

    vars = SourceVariables(c)
    sel = (vars.group_by, vars.helpers, vars.inputs, vars.targets, to_stringlist(vars.weights))
    q = From(source) |>
        filter_training(vars.partition) |>
        sort_columns(vars.order_by) |>
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

    vars = SourceVariables(c)

    q = From(source) |>
        sort_columns(vars.order_by) |>
        select_columns([id_var], vars.group_by, vars.helpers, vars.inputs)
    t = DBInterface.execute(fromtable, repository, q; schema)

    model = jlddeserialize(state.content)
    pred_table, new_state = _with_state(c(model, t, id_var))
    load_table(repository, pred_table, destination; schema)
    cols = String[string(k) for k in Tables.columnnames(Tables.columns(pred_table))]
    columns = setdiff(cols, [id_var])
    return isnothing(new_state) ? columns : (columns, new_state)
end
