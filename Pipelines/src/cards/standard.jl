abstract type StandardCard <: Card end

# StandardCard interface (instances must also be callable)

function weights end
function sorters end

function partition end
function predictors end
function targets end
function outputs end

function _train end

# Implementation of Card methods

invertible(::StandardCard) = false

inputs(c::StandardCard) = stringlist(predictors(c), targets(c), sorters(c), weights(c), partition(c))

function train(
        repository::Repository, c::StandardCard, source::AbstractString;
        schema = nothing
    )

    ns = colnames(repository, source; schema)
    id_col = get_id_col(ns)
    wts_col = weights(c)
    q = id_table(source, id_col) |>
        filter_partition(partition(c)) |>
        sort_columns(sorters(c)) |>
        select_columns(id_col, wts_col, predictors(c), targets(c))

    t = DBInterface.execute(fromtable, repository, q; schema)
    id = pop!(t, id_col)
    model = if isnothing(wts_col)
        _train(c, t, id)
    else
        wts = pop!(t, wts_col)
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
        sort_columns(sorters(c)) |>
        select_columns(id_col, predictors(c))
    t = DBInterface.execute(fromtable, repository, q; schema)
    id = pop!(t, id_col)

    ks = outputs(c)
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
