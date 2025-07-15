# StandardCard interface:
# - `_train(c, tbl, id; weights) -> model`
# - `(c)(model, tbl, id) -> new_tbl, new_id`

# Implementation of Card methods

function train(
        repository::Repository, c::StandardCard, source::AbstractString;
        schema = nothing
    )

    ns = colnames(repository, source; schema)
    id_col = get_id_col(ns)
    q = id_table(source, id_col) |>
        filter_partition(partition_var(c)) |>
        sort_columns(sorting_vars(c)) |>
        select_columns([id_col], input_vars(c), target_vars(c), grouping_vars(c), weight_vars(c))

    t = DBInterface.execute(fromtable, repository, q; schema)
    id = pop!(t, id_col)
    model = if isnothing(weight_var(c))
        _train(c, t, id)
    else
        wts = pop!(t, weight_var(c))
        _train(c, t, id, weights = wts)
    end
    return CardState(content = jldserialize(model))
end

function evaluate(
        repository::Repository,
        c::StandardCard,
        state::CardState,
        (source, destination)::Pair;
        schema = nothing
    )
    ns = colnames(repository, source; schema)
    id_col = get_id_col(ns)
    q = id_table(source, id_col) |>
        sort_columns(sorting_vars(c)) |>
        select_columns([id_col], input_vars(c), grouping_vars(c))
    t = DBInterface.execute(fromtable, repository, q; schema)
    id = pop!(t, id_col)

    ks = output_vars(c)
    model = jlddeserialize(state.content)
    pred_table, id′ = c(model, t, id)
    id_col′ = get_id_col(keys(pred_table))
    pred_table[id_col′] = id′

    return with_table(repository, pred_table; schema) do tbl_name
        query = id_table(source, id_col) |>
            LeftJoin(tbl_name => From(tbl_name), on = Get(id_col) .== Get(id_col′, over = Get(tbl_name))) |>
            Select((ns .=> Get.(ns))..., (ks .=> Get.(ks, over = Get(tbl_name)))...)
        replace_table(repository, query, destination; schema)
    end
end
