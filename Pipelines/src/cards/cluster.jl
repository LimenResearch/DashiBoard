const CLUSTERING_OPTIONS_REGEX = r"^clustering_options\.(.*)$"

_kmeans(X; classes, options...) = kmeans(X, classes; options...)
_dbscan(X; radius, options...) = dbscan(X, radius; options...)

struct Clusterer
    method::Base.Callable
    trainable::Bool
end

const CLUSTERERS = OrderedDict{String, Clusterer}(
    "kmeans" => Clusterer(_kmeans, true),
    "dbscan" => Clusterer(_dbscan, false),
)

struct ClusterCard <: AbstractCard
    clusterer::Clusterer
    model_options::Dict{Symbol, Any}
    training_options::Dict{Symbol, Any}
    columns::Vector{String}
    partition::Union{String, Nothing}
    output::String
end

function ClusterCard(c::AbstractDict)
    method::String = c[:method]
    clusterer::Clusterer = CLUSTERER[method]
    model_options::Dict{Symbol, Any} = extract_options(c, :model_options, MODEL_OPTIONS_REGEX)
    training_options::Dict{Symbol, Any} = extract_options(c, :training_options, TRAINING_OPTIONS_REGEX)
    columns::Vector{String} = c[:columns]
    output::String = get(c, :output, "cluster")
    return ClusterCard(
        clusterer,
        model_options,
        training_options,
        columns,
        partition,
        output
    )
end

function get_training_options(d::AbstractDict{Symbol})
    options = Dict{Symbol, Any}(
        :maxiter => get(d, :iterations, nothing),
        :tol => get(d, :tol, nothing),
    )
    filter!(!isnothing ∘ last, options)
    return options
end

function get_training_options(cc::ClusterCard)
    return if cc.clusterer.trainable
        get_training_options(cc.training_options)
    else
        Dict{Symbol, Any}()
    end
end

invertible(::ClusterCard) = false

inputs(cc::ClusterCard) = stringset(cc.columns, cc.partition)

outputs(cc::ClusterCard) = stringset(cc.output)

function train(repository::Repository, cc::ClusterCard, source::AbstractString; schema = nothing)
    ns = colnames(repository, source; schema)
    id_col = get_id_col(ns)
    q = id_table(source, id_col) |>
        filter_partition(cc.partition) |>
        Select(Get(id_col), Get.(cc.columns)...)
    t = DBInterface.execute(fromtable, repository, q; schema)
    X = stack(Fix1(getindex, t), cc.columns, dims = 1)
    training_options = get_training_options(cc)
    id = t[id_col]
    model = cc.clusterer.method(X; cc.model_options..., training_options...)
    return CardState(
        content = jldserialize((; id, model))
    )
end

function evaluate(
        repository::Repository,
        cc::ClusterCard,
        state::CardState,
        (source, destination)::Pair;
        schema = nothing
    )

    ns = colnames(repository, source; schema)
    id_col = get_id_col(ns)

    (; id, model) = jlddeserialize(state.content)
    pred_table = Dict{String, Any}(
        id_col => id,
        cc.output => assignments(model)
    )

    # as `predict` is not implemented, we cannot fill in data points outside partition
    # https://github.com/JuliaStats/Clustering.jl/issues/63
    return with_table(repository, pred_table; schema) do tbl_name
        query = id_table(source, id_col) |>
            LeftJoin(From(tbl_name), on = Get(id_col) .== Get(id_col, over = Get(tbl_name))) |>
            Define(cc.output => Get(cc.output, over = Get(tbl_name)))
        replace_table(repository, query, target; schema)
    end
end
