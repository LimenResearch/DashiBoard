abstract type StandardCard <: Card end

# StandardCard interface (instances must also be callable)

function partition end
function columns end
function outputs end

function _train end

# Implementation of Card methods

invertible(::StandardCard) = false

inputs(c::StandardCard) = stringlist(columns(c), partition(c))

function train(
        repository::Repository, c::StandardCard, source::AbstractString;
        schema = nothing
    )

    q = From(source) |> filter_partition(partition(c)) |> Select(Get.(columns(c))...)
    t = DBInterface.execute(fromtable, repository, q; schema)
    model = _train(c, t)

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
    q = id_table(source, id_col) |> Select(Get(id_col), Get.(columns(c))...)
    t = DBInterface.execute(fromtable, repository, q; schema)
    id = pop!(t, id_col)

    model = jlddeserialize(state.content)
    pred_table = c(model, t)
    pred_table[id_col] = id
    ks = outputs(c)

    return with_table(repository, pred_table; schema) do tbl_name
        query = id_table(source, id_col) |>
            Join(tbl_name => From(tbl_name), on = Get(id_col) .== Get(id_col, over = Get(tbl_name))) |>
            Select((ns .=> Get.(ns))..., (ks .=> Get.(ks, over = Get(tbl_name)))...)
        replace_table(repository, query, destination; schema)
    end
end
