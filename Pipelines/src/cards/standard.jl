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
    q = with_id(source, id_var) |>
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
        (source, destination)::Pair;
        schema = nothing
    )

    ns = colnames(repository, source; schema)
    id_var = new_name("id", ns, get_outputs(c))
    id_table = with_id(source, id_var)

    q = id_table |>
        sort_columns(sorting_vars(c)) |>
        select_columns([id_var], input_vars(c), grouping_vars(c))
    t = DBInterface.execute(fromtable, repository, q; schema)
    id = pop!(t, id_var)

    ks = output_vars(c)
    model = jlddeserialize(state.content)
    pred_table, new_id = c(model, t, id)
    pred_table[id_var] = new_id

    return with_table(repository, pred_table; schema) do tbl_name
        query = id_table |>
            LeftJoin(tbl_name => From(tbl_name), on = Get(id_var) .== Get(id_var, over = Get(tbl_name))) |>
            Select((ns .=> Get.(ns))..., (ks .=> Get.(ks, over = Get(tbl_name)))...)
        replace_table(repository, query, destination; schema)
    end
end
