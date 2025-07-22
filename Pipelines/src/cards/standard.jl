# StandardCard interface:
# - `_train(c, tbl, id; weights) -> model`
# - `(c)(model, tbl, id) -> new_tbl, new_id`

# Implementation of Card methods

function train(
        repository::Repository, c::StandardCard, source::AbstractString;
        schema = nothing
    )

    id_var = new_name("id", get_inputs(c), get_outputs(c))
    wt_var = weight_var(c)
    q = From(source) |>
        Partition() |>
        Define(id_var => Agg.row_number()) |>
        filter_partition(partition_var(c)) |>
        sort_columns(sorting_vars(c)) |>
        select_columns([id_var], input_vars(c), target_vars(c), grouping_vars(c), to_stringlist(wt_var))

    t = DBInterface.execute(fromtable, repository, q; schema)
    id = pop!(t, id_var)
    model = if isnothing(wt_var)
        _train(c, t, id)
    else
        wts = pop!(t, wt_var)
        _train(c, t, id, weights = wts)
    end
    return CardState(content = jldserialize(model))
end

function evaluate(
        repository::Repository,
        c::StandardCard,
        state::CardState,
        (source, destination)::Pair,
        id_var::AbstractString;
        schema = nothing
    )

    q = From(source) |>
        Partition() |>
        Define(id_var => Agg.row_number()) |>
        sort_columns(sorting_vars(c)) |>
        select_columns([id_var], input_vars(c), grouping_vars(c))
    t = DBInterface.execute(fromtable, repository, q; schema)
    id = pop!(t, id_var)

    model = jlddeserialize(state.content)
    pred_table, new_id = c(model, t, id)
    pred_table[id_var] = new_id

    load_table(repository, pred_table, destination; schema)
    return
end
