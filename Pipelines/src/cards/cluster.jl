function _kmeans(X; classes, iterations = 100, tol = 1.0e-6, seed = nothing, options...)
    return kmeans(X, classes; maxiter = iterations, tol, rng = get_rng(seed), options...)
end

_dbscan(X; radius, options...) = dbscan(X, radius; options...)

const CLUSTERING_FUNCTIONS = OrderedDict{String, Function}(
    "kmeans" => _kmeans,
    "dbscan" => _dbscan,
)

struct Clusterer
    method::Function
    options::Dict{Symbol, Any}
end

function Clusterer(method_name::AbstractString, d::AbstractDict)
    method = CLUSTERING_FUNCTIONS[method_name]
    options = make(SymbolDict, d)
    # TODO: add preprocess for, e.g., metrics
    return Clusterer(method, options)
end

# TODO: support weights and custom metrics
"""
    struct ClusterCard <: Card
        clusterer::Clusterer
        columns::Vector{String}
        partition::Union{String, Nothing}
        output::String
    end

Cluster `columns` based on `clusterer`.
Save resulting column as `output`.
"""
struct ClusterCard <: Card
    clusterer::Clusterer
    columns::Vector{String}
    partition::Union{String, Nothing}
    output::String
end

register_card("cluster", ClusterCard)

function ClusterCard(c::AbstractDict)
    method_name::String = c["method"]
    method_options::StringDict = extract_options(c, "method_options", METHOD_OPTIONS_REGEX)
    clusterer::Clusterer = Clusterer(method_name, method_options)
    columns::Vector{String} = c["columns"]
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    output::String = get(c, "output", "cluster")
    return ClusterCard(
        clusterer,
        columns,
        partition,
        output
    )
end

invertible(::ClusterCard) = false

inputs(cc::ClusterCard) = stringlist(cc.columns, cc.partition)
outputs(cc::ClusterCard) = [cc.output]

function train(repository::Repository, cc::ClusterCard, source::AbstractString; schema = nothing)
    ns = colnames(repository, source; schema)
    id_col = get_id_col(ns)
    q = id_table(source, id_col) |>
        filter_partition(cc.partition) |>
        Select(Get(id_col), Get.(cc.columns)...)
    t = DBInterface.execute(fromtable, repository, q; schema)
    X = stack(Fix1(getindex, t), cc.columns, dims = 1)
    id = t[id_col]
    model = cc.clusterer.method(X; cc.clusterer.options...)
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
    pred_table = Dict{String, AbstractVector}(
        id_col => id,
        cc.output => assignments(model)
    )

    # as `predict` is not implemented, we cannot fill in data points outside partition
    # https://github.com/JuliaStats/Clustering.jl/issues/63
    return with_table(repository, pred_table; schema) do tbl_name
        query = id_table(source, id_col) |>
            LeftJoin(tbl_name => From(tbl_name), on = Get(id_col) .== Get(id_col, over = Get(tbl_name))) |>
            Select((ns .=> Get.(ns))..., cc.output => Get(cc.output, over = Get(tbl_name)))
        replace_table(repository, query, destination; schema)
    end
end

function CardWidget(::Type{ClusterCard})

    method_names = collect(keys(CLUSTERING_FUNCTIONS))

    fields = Widget[
        Widget("method", options = method_names),
        Widget("columns"),
        Widget("partition", required = false),
        Widget("output"),
    ]

    for (idx, m) in enumerate(method_names)
        method_config = parse_toml_config("cluster", m)
        wdgs = get(method_config, "widgets", AbstractDict[])
        append!(fields, generate_widget.(wdgs, "method", m, idx))
    end

    return CardWidget(;
        type = "cluster",
        label = "Cluster",
        output = OutputSpec("output"),
        fields
    )
end
