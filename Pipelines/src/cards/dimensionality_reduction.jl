function _pca(X, maxoutdim)
    return fit(PCA, X; maxoutdim)
end

function _ppca(X, maxoutdim; iterations = 1000, tol = 1.0e-6)
    return fit(PPCA, X; maxoutdim, maxiters = iterations, tol)
end

function _factoranalysis(X, maxoutdim; iterations = 1000, tol = 1.0e-6)
    return fit(FactorAnalysis, X; maxoutdim, maxiters = iterations, tol)
end

function _mds(X, maxoutdim)
    return fit(MDS, X; maxoutdim)
end

const PROJECTION_FUNCTIONS = OrderedDict{String, Function}(
    "pca" => _pca,
    "ppca" => _ppca,
    "factoranalysis" => _factoranalysis,
    "mds" => _mds,
)

struct Projector
    method::Function
    options::Dict{Symbol, Any}
end

"""
    struct DimensionalityReductionCard <: AbstractCard
        projector::Projector
        columns::Vector{String}
        maxoutdim::Int
        partition::Union{String, Nothing}
        output::String
    end

Project `columns` based on `projector`.
Save resulting column as `output`.
"""
struct DimensionalityReductionCard <: AbstractCard
    projector::Projector
    columns::Vector{String}
    maxoutdim::Int
    partition::Union{String, Nothing}
    output::String
end

register_card("dimensionality_reduction", DimensionalityReductionCard)

function DimensionalityReductionCard(c::AbstractDict)
    method_name::String = c[:method]
    method_options::Dict{Symbol, Any} = extract_options(c, :method_options, METHOD_OPTIONS_REGEX)
    projector::Projector = Projector(method_name, method_options)
    columns::Vector{String} = c[:columns]
    maxoutdim::Int = c[:maxoutdim]
    partition::Union{String, Nothing} = get(c, :partition, nothing)
    output::String = get(c, :output, "cluster")
    return ClusterCard(
        projector,
        columns,
        maxoutdim,
        partition,
        output
    )
end

function train(
        repository::Repository,
        drc::DimensionalityReductionCard,
        source::AbstractString;
        schema = nothing
    )

    ns = colnames(repository, source; schema)
    id_col = get_id_col(ns)
    q = id_table(table, id_col) |>
        filter_partition(drc.partition) |> 
        Select(Get.(drc.columns)...)

    t = DBInterface.execute(fromtable, repository, q; schema)
    X = stack(Fix1(getindex, t), drc.columns, dims = 1)
    model = drc.projector.method(X, drc.maxoutdim; drc.projector.options...)
    return CardState(
        content = jldserialize(model)
    )
end

function evaluate(
        repository::Repository,
        drc::DimensionalityReductionCard,
        state::CardState,
        (source, destination)::Pair;
        schema = nothing
    )

    ns = colnames(repository, source; schema)
    id_col = get_id_col(ns)
    q = id_table(table, id_col) |>
        Select(Get(id_col), Get.(drc.columns)...)

    model = jlddeserialize(state.content)

    t = DBInterface.execute(fromtable, repository, q; schema)
    X = stack(Fix1(getindex, t), drc.columns, dims = 1)
    Y = predict(model, X)
    M, N = size(Y)
    ks = string.(drc.output, "_", 1:drc.maxoutdim)

    pred_table = Dict{String, AbstractVector}(
        id_col => t[id_col],
    )
    for (i, k) in enumerate(keys)
        pred_table[k] = i ≤ M ? Y[i, :] : fill(missing, N)
    end

    return with_table(repository, pred_table; schema) do tbl_name
        query = id_table(source, id_col) |>
            Join(tbl_name => From(tbl_name), on = Get(id_col) .== Get(id_col, over = Get(tbl_name))) |>
            Select((ns .=> Get.(ns))..., (ks .=> Get(ks, over = Get(tbl_name)))...)
        replace_table(repository, query, destination; schema)
    end
end

function CardWidget(::Type{DimensionalityReductionCard})

    method_names = collect(keys(PROJECTION_FUNCTIONS))

    fields = Widget[
        Widget("method", options = method_names),
        Widget("columns"),
        Widget("maxoutdim"),
        Widget("partition", required = false),
        Widget("output"),
    ]

    for (idx, m) in enumerate(method_names)
        method_config = parseconfig("dimensionality_reduction", m)
        wdgs = get(method_config, "widgets", AbstractDict[])
        append!(fields, generate_widget.(wdgs, :method, m, idx))
    end

    return CardWidget(;
        type = "dimensionality_reduction",
        label = "Dimensionality Reduction",
        output = OutputSpec("output", nothing, "maxoutdim"),
        fields
    )
end
