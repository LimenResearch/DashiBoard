# StandardCard interface:
# - `_train(c, tbl, id; weights) -> model`
# - `(c)(model, tbl, id) -> new_tbl, new_id`

# Helper function

function get_weights(c::StandardCard, t::SimpleTable, f = identity)
    var = weight_var(c)
    return isnothing(var) ? nothing : f(t[var])
end

# Implementation of Card methods

function train(
        repository::Repository, c::StandardCard,
        source::AbstractString, id_var::AbstractPrimaryKey;
        schema = nothing
    )

    wt_var = weight_var(c)
    q = From(source) |>
        filter_partition(partition_var(c)) |>
        sort_columns(sorting_vars(c)) |>
        select_columns([id_var], input_vars(c), target_vars(c), grouping_vars(c), to_stringlist(wt_var))

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
        schema = nothing
    )

    q = From(source) |>
        sort_columns(sorting_vars(c)) |>
        select_columns([id_var], input_vars(c), grouping_vars(c))
    t = DBInterface.execute(fromtable, repository, q; schema)

    model = jlddeserialize(state.content)
    pred_table = c(model, t, id_var)
    load_table(repository, pred_table, destination; schema)
    cols = String[string(k) for k in Tables.columnnames(Tables.columns(pred_table))]
    return setdiff(cols, [id_var])
end
