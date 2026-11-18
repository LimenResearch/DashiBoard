"""
    AnomalyMethod <: AbstractMethod

An unsupervised anomaly detector and its options, selected in the anomaly card's JSON by `"type"`
(see `ANOMALY_METHODS`). Concrete types are functors `(m)(X)` fitting the d×N input matrix `X` of
the training rows and returning a detector `D`, with `anomaly_score(D, X)` scoring the columns of
any d×M matrix: the higher the score, the more anomalous the row.
"""
abstract type AnomalyMethod <: AbstractMethod end

## Isolation forest

# A node of an isolation tree, stored flat. `feature == 0` marks a leaf holding `size` rows.
struct IsolationNode
    feature::Int
    threshold::Float64
    left::Int
    right::Int
    size::Int
end

struct IsolationForest
    trees::Vector{Vector{IsolationNode}}
    sample_size::Int
end

const EULER_GAMMA = 0.5772156649015329

# Average path length of an unsuccessful binary-search-tree search among `n` points
# (Liu, Ting & Zhou 2008): the normalisation of path lengths.
function average_path_length(n::Integer)
    n > 2 && return 2 * (log(n - 1) + EULER_GAMMA) - 2 * (n - 1) / n
    return n == 2 ? 1.0 : 0.0
end

function grow_isolation_tree!(nodes, X, idx, depth, max_depth, rng)
    n = length(idx)
    if depth ≥ max_depth || n ≤ 1
        push!(nodes, IsolationNode(0, 0.0, 0, 0, n))
        return length(nodes)
    end
    # only features that vary among these rows can split them
    ranges = [extrema(view(X, f, idx)) for f in axes(X, 1)]
    candidates = findall(r -> r[1] < r[2], ranges)
    if isempty(candidates)
        push!(nodes, IsolationNode(0, 0.0, 0, 0, n))
        return length(nodes)
    end
    f = candidates[rand(rng, 1:length(candidates))]
    lo, hi = ranges[f]
    threshold = lo + rand(rng) * (hi - lo)
    left_idx = filter(i -> X[f, i] < threshold, idx)
    right_idx = filter(i -> X[f, i] ≥ threshold, idx)
    push!(nodes, IsolationNode(f, threshold, 0, 0, n))
    k = length(nodes)
    l = grow_isolation_tree!(nodes, X, left_idx, depth + 1, max_depth, rng)
    r = grow_isolation_tree!(nodes, X, right_idx, depth + 1, max_depth, rng)
    nodes[k] = IsolationNode(f, threshold, l, r, n)
    return k
end

function path_length(tree::Vector{IsolationNode}, x::AbstractVector)
    k, depth = 1, 0
    while true
        node = tree[k]
        node.feature == 0 && return depth + average_path_length(node.size)
        k = x[node.feature] < node.threshold ? node.left : node.right
        depth += 1
    end
end

"""
    IsolationForestMethod <: AnomalyMethod

Isolation forest (`"type" => "isolation_forest"`; Liu, Ting & Zhou 2008): `trees` random trees, each
grown on `sample_size` training rows drawn without replacement, split on a random feature at a
random threshold until each row is alone or the depth reaches ⌈log₂ sample_size⌉. Anomalies are
isolated in few splits. The score is `2^(-E[h(x)] / c(sample_size))` in (0, 1): above about 0.6
reads as anomalous, around 0.5 or below as normal. Splits are axis-aligned, so the score does not
depend on the scale of each input. `seed` makes the forest reproducible.
"""
@kwarg struct IsolationForestMethod <: AnomalyMethod
    trees::Int = 100 & (dashi = IntegerIR(minimum = 1),)
    sample_size::Int = 256 & (dashi = IntegerIR(minimum = 2),)
    seed::Maybe{Int} = nothing & (dashi = IntegerIR(minimum = 0),)
end

function (m::IsolationForestMethod)(X::AbstractMatrix)
    rng = get_rng(m.seed)
    N = size(X, 2)
    ψ = min(m.sample_size, N)
    max_depth = ceil(Int, log2(max(ψ, 2)))
    trees = map(1:m.trees) do _
        idx = sample(rng, 1:N, ψ; replace = false)
        nodes = IsolationNode[]
        grow_isolation_tree!(nodes, X, idx, 0, max_depth, rng)
        nodes
    end
    return IsolationForest(trees, ψ)
end

function anomaly_score(forest::IsolationForest, X::AbstractMatrix)
    c = average_path_length(forest.sample_size)
    return map(eachcol(X)) do x
        h = sum(tree -> path_length(tree, x), forest.trees) / length(forest.trees)
        c > 0 ? 2.0^(-h / c) : 0.5
    end
end

## Mahalanobis distance

struct MahalanobisDetector
    μ::Vector{Float64}
    L::Matrix{Float64}  # lower Cholesky factor of the regularised covariance
end

"""
    MahalanobisMethod <: AnomalyMethod

Mahalanobis distance (`"type" => "mahalanobis"`) from the mean of the training rows, under their
covariance. `regularization` adds that fraction of the average variance to the diagonal, so that
collinear or constant inputs still give a definite covariance. Assumes one roughly elliptical
cloud of normal rows; the score is the distance itself (≥ 0), scale-free.
"""
@kwarg struct MahalanobisMethod <: AnomalyMethod
    regularization::Float64 = 1.0e-6 & (dashi = NumberIR(minimum = 0),)
end

function (m::MahalanobisMethod)(X::AbstractMatrix)
    μ, Σ = mean_and_cov(X, 2)
    d = size(Σ, 1)
    λ = m.regularization * max(tr(Σ) / d, eps())
    C = cholesky(Symmetric(Σ + λ * I))
    return MahalanobisDetector(vec(μ), Matrix(C.L))
end

anomaly_score(md::MahalanobisDetector, X::AbstractMatrix) =
    vec(sqrt.(sum(abs2, LowerTriangular(md.L) \ (X .- md.μ), dims = 1)))

## PCA reconstruction error

struct PCADetector{P}
    μ::Vector{Float64}
    σ::Vector{Float64}
    pca::P
end

"""
    PCAReconstructionMethod <: AnomalyMethod

PCA reconstruction error (`"type" => "pca_reconstruction"`): the inputs are standardised with the
mean and standard deviation of the training rows, projected on their first `n_components`
principal components and reconstructed; the score is the Euclidean norm of what the projection
misses. Rows that break the correlations among the inputs score high even when no single input is
extreme.
"""
@kwarg struct PCAReconstructionMethod <: AnomalyMethod
    n_components::Int & (dashi = IntegerIR(minimum = 1),)
end

function (m::PCAReconstructionMethod)(X::AbstractMatrix)
    μ, σ = mean_and_std(X, 2)
    σ = map(s -> s > 0 ? s : 1.0, vec(σ))
    Z = (X .- vec(μ)) ./ σ
    pca = fit(PCA, Z; maxoutdim = m.n_components)
    return PCADetector(vec(μ), σ, pca)
end

function anomaly_score(pd::PCADetector, X::AbstractMatrix)
    Z = (X .- pd.μ) ./ pd.σ
    Ẑ = reconstruct(pd.pca, predict(pd.pca, Z))
    return vec(sqrt.(sum(abs2, Z - Ẑ, dims = 1)))
end

const ANOMALY_METHODS = OrderedDict{String, Type}(
    "isolation_forest" => IsolationForestMethod,
    "mahalanobis" => MahalanobisMethod,
    "pca_reconstruction" => PCAReconstructionMethod,
)

@options AnomalyMethod ANOMALY_METHODS

"""
    @kwarg struct AnomalyCard{M <: AnomalyMethod} <: StandardCard
        method::M
        inputs::Vector{String}
        partition::Union{String, Nothing} = nothing
        output::String = "anomaly_score"
    end

Fit the unsupervised detector `method` on `inputs` in the training rows (`partition`), then score
every row. Save the score as `output`: the higher, the more anomalous. Unlike clustering, a fitted
detector scores rows it was not trained on, so a baseline period can be scored against later ones.
"""
@kwarg struct AnomalyCard{M <: AnomalyMethod} <: StandardCard
    method::M
    inputs::Vector{String} & (dashi = NONEMPTY_VARIABLES_DEF,)
    partition::Maybe{String} = nothing & (dashi = VARIABLE_DEF,)
    output::String = "anomaly_score" & (dashi = StringIR(minLength = 1),)
end

## StandardCard interface

SourceVariables(ac::AnomalyCard) = SourceVariables(; ac.inputs, ac.partition)

output_spec(ac::AnomalyCard) = [OutputGroup(OutputSpec([ac.output]))]

_input_matrix(ac::AnomalyCard, t) = Matrix{Float64}(stack(Fix1(getindex, t), ac.inputs, dims = 1))

_train(ac::AnomalyCard, t, ::AbstractPrimaryKey) = ac.method(_input_matrix(ac, t))

function (ac::AnomalyCard)(model, t, id_var::AbstractPrimaryKey)
    scores = anomaly_score(model, _input_matrix(ac, t))
    return SimpleTable(id_var => t[id_var], ac.output => scores)
end
