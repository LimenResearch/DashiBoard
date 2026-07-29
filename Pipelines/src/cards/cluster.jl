"""
    ClusteringMethod <: AbstractMethod

A clustering algorithm and its options, selected in the cluster card's
JSON by `"type"` (see `CLUSTERING_METHODS`). Concrete types are functors
`(m)(X; weights)` fitting the d×N input matrix `X`.
"""
abstract type ClusteringMethod <: AbstractMethod end

"""
    KMeansMethod{D <: DissimilarityMethod} <: ClusteringMethod

k-means (`"type" => "kmeans"`) into a predeclared number of `classes`.
Accepts any [`DissimilarityMethod`](@ref); the default, squared Euclidean,
is the canonical k-means objective — under any other dissimilarity the
center update remains the arithmetic mean (only the true minimizer for
squared Euclidean), so the fit becomes a reasonable heuristic without the
usual convergence guarantee.
"""
@kwarg struct KMeansMethod{D <: DissimilarityMethod} <: ClusteringMethod
    dissimilarity::D = SqEuclideanMethod()
    classes::Int & (dashi = json_integer(minimum = 1),)
    iterations::Int = 100 & (dashi = json_integer(minimum = 1),)
    tol::Float64 = 1.0e-6 & (dashi = json_number(exclusiveMinimum = 0),)
    seed::Union{Int, Nothing} = nothing & (dashi = json_integer(minimum = 0),)
    # how the initial centers are seeded: k-means++, uniformly at random, or
    # the points of extreme centrality (Clustering.jl's :kmpp/:rand/:kmcen)
    init::String = "kmpp" & (dashi = json_string(enum = ["kmpp", "rand", "kmcen"]),)
end

function (m::KMeansMethod)(X; weights)
    (; classes, iterations, tol, seed) = m
    distance = get_dissimilarity(m.dissimilarity)
    return kmeans(
        X, classes;
        maxiter = iterations, tol, rng = get_rng(seed), weights, distance,
        init = Symbol(m.init),
    )
end

"""
    DBSCANMethod{D <: MetricMethod} <: ClusteringMethod

DBSCAN (`"type" => "dbscan"`): density-based clusters of points within
`radius` of each other, with the number of clusters coming from the data;
sparse rows are labeled 0 (noise). The dissimilarity is restricted to
[`MetricMethod`](@ref) — the KD-tree behind the fit requires the triangle
inequality — so parsing and the schema only accept true metrics.
"""
@kwarg struct DBSCANMethod{D <: MetricMethod} <: ClusteringMethod
    dissimilarity::D = EuclideanMethod()
    radius::Float64 & (dashi = json_number(exclusiveMinimum = 0),)
    min_neighbors::Int = 1 & (dashi = json_integer(minimum = 1),)
    min_cluster_size::Int = 1 & (dashi = json_integer(minimum = 1),)
end

function (m::DBSCANMethod)(X; weights)
    (; radius, min_neighbors, min_cluster_size) = m
    isnothing(weights) || @warn "Weights not supported in DBSCAN"
    metric = get_dissimilarity(m.dissimilarity)
    return dbscan(X, radius; metric, min_neighbors, min_cluster_size)
end

"""
    AffinityPropagationMethod <: ClusteringMethod

Affinity propagation (`"type" => "affinity_propagation"`): points exchange
messages until a set of exemplars — actual fitted points — emerges, so the
number of clusters comes from the data instead of being predeclared.
`damp`, `maxiter` and `tol` control the message passing. The similarity
matrix is the negative squared Euclidean distance over the card's `inputs`,
built densely: the fit is O(N²) in the training rows. Each point's
self-similarity (its preference; more negative → fewer clusters) is set to
the median of its similarities, the classic default for a moderate number
of clusters.
"""
@kwarg struct AffinityPropagationMethod <: ClusteringMethod
    damp::Float64 = 0.5 & (dashi = json_number(minimum = 0, exclusiveMaximum = 1),)
    maxiter::Int = 200 & (dashi = json_integer(minimum = 1),)
    tol::Float64 = 1.0e-6 & (dashi = json_number(exclusiveMinimum = 0),)
end

"""
    _labels(res)

Which cluster the fit put each ROW in. Most methods hand back a Clustering.jl
result; a method that fits *transformed* data returns the per-row labels it
mapped back itself.
"""
_labels(res) = assignments(res)
_labels(labels::AbstractVector{<:Integer}) = labels

"""
    _collapse_duplicates(X)

Distinct columns of `X` in first-occurrence order, how many rows each stands
for, and the row -> distinct-point map.
"""
function _collapse_duplicates(X)
    groups = OrderedDict{Vector{Float64}, Int}()
    counts, row_group = Int[], Vector{Int}(undef, size(X, 2))
    for (j, x) in enumerate(eachcol(X))
        g = get!(groups, convert(Vector{Float64}, x)) do
            push!(counts, 0)
            length(counts)
        end
        counts[g] += 1
        row_group[j] = g
    end
    return stack(keys(groups)), counts, row_group
end

#=
Duplicate rows are collapsed into count weights before the fit. Repeated
identical points otherwise keep affinity propagation's messages oscillating,
and real data is full of them — calls from one address, readings from one
sensor. The reduction is exact rather than a sample: similarities are scaled
by the assignee's count so a distinct point pulls as hard as its copies would
have, while the diagonal preferences stay unscaled, since a point is free to
be its own exemplar however many copies it has, and the preference itself is
the count-weighted median. Labels come back per distinct point, so they are
expanded to the original rows before returning.
=#
function (m::AffinityPropagationMethod)(X; weights)
    (; damp, maxiter, tol) = m
    isnothing(weights) || @warn "Weights not supported in affinity propagation"
    U, counts, row_group = _collapse_duplicates(X)
    # `affinityprop` needs at least two points; one distinct point is
    # trivially its own exemplar
    size(U, 2) == 1 && return ones(Int, size(X, 2))
    S = -pairwise(SqEuclidean(), U, dims = 2)
    p = [median(view(S, :, j), fweights(counts)) for j in axes(S, 2)]
    S .*= counts
    S[diagind(S)] .= p
    res = affinityprop(S; maxiter, tol, damp)
    res.converged ||
        @warn "Affinity propagation did not converge; increase `maxiter` or adjust `damp`"
    return assignments(res)[row_group]
end

const CLUSTERING_METHODS = OrderedDict{String, Type}(
    "kmeans" => KMeansMethod,
    "dbscan" => DBSCANMethod,
    "affinity_propagation" => AffinityPropagationMethod,
)

@options ClusteringMethod CLUSTERING_METHODS

# TODO: support custom metrics
"""
    struct ClusterCard{M <: ClusteringMethod} <: StandardCard
        method::M
        inputs::Vector{String}
        weights::Union{String, Nothing} = nothing
        partition::Union{String, Nothing} = nothing
        output::String = "cluster"
        threshold::Float64 = 0.5
        lineage::Bool = false
        memory::Union{Int, Nothing} = nothing
    end

Cluster `inputs` based on `method`. Save resulting column as `output`.

Training keeps its members — the rows it saw, their `inputs`, and the label each
received. Evaluation then **refits on those members plus whatever rows are new**
and reconciles the two clusterings by shared membership, so a cluster keeps its
identity from one evaluation to the next instead of being renumbered. No
assignment rule could do this: training is transitive, whereas assigning against
a frozen fit is one-shot, so a cluster could never grow.

`threshold` is how much of a refit cluster's previously-labelled rows must come
from one stored cluster for it to inherit that cluster's label; below it, the
cluster is new. It is the sensitivity knob — high means more things count as new.

`lineage` makes evaluation roll the stored members forward, so the model
accumulates what it has seen. It is off by default because it makes evaluation
stateful: the node is updated, and evaluating on new rows twice does not give
the same answer. An evaluation that adds no rows changes nothing, so re-running
one is always safe. `memory` bounds the accumulation, dropping members from more
than that many iterations back — an iteration being a time the model actually
grew.
"""
@kwarg struct ClusterCard{M <: ClusteringMethod} <: StandardCard
    method::M
    inputs::Vector{String} & (dashi = JSON_NONEMPTY_VARIABLES,)
    weights::Union{String, Nothing} = nothing & (dashi = JSON_VARIABLE,)
    partition::Union{String, Nothing} = nothing & (dashi = JSON_VARIABLE,)
    output::String = "cluster" & (dashi = json_string(minLength = 1),)
    threshold::Float64 = 0.5 & (dashi = json_number(exclusiveMinimum = 0, maximum = 1),)
    lineage::Bool = false
    memory::Union{Int, Nothing} = nothing & (dashi = json_integer(minimum = 1),)
end

## StandardCard interface

SourceVariables(cc::ClusterCard) = SourceVariables(; cc.inputs, cc.weights, cc.partition)

OutputVariables(cc::ClusterCard) = OutputVariables([cc.output])

# Columns the member table adds to the card's own; an input of either name would
# be shadowed, so `_member_table` refuses rather than silently overwrite.
const MEMBER_LABEL = "label"
const MEMBER_ORIGIN = "iteration_origin"

"""
    _diagnostics(method, res)

Method-specific material worth keeping for *inspecting* a fit — a reachability
graph, generative parameters, centers — as distinct from what evaluation needs,
which is the member table. Methods opt in; by default nothing is kept.
"""
_diagnostics(::ClusteringMethod, res) = nothing

"""
    _member_columns(cc::ClusterCard, id_var)

The columns a refit needs: the id, the inputs, and the weights column when there
is one. Deduplicated, since `weights` may also be an input.
"""
function _member_columns(cc::ClusterCard, id_var::AbstractPrimaryKey)
    cols = [id_var; cc.inputs]
    isnothing(cc.weights) || push!(cols, cc.weights)
    return unique(cols)
end

"""
    _member_table(cc, t, id_var, label, origin)

One row per fitted row: what a refit needs, plus the label the fit gave it and
the iteration it entered the model on.
"""
function _member_table(cc::ClusterCard, t, id_var::AbstractPrimaryKey, label, origin::Integer)
    cols = _member_columns(cc, id_var)
    for reserved in (MEMBER_LABEL, MEMBER_ORIGIN)
        reserved in cols && throw(
            ArgumentError("`$reserved` is reserved by the cluster state; rename that column")
        )
    end
    members = SimpleTable()
    for col in cols
        members[col] = t[col]
    end
    members[MEMBER_LABEL] = label
    members[MEMBER_ORIGIN] = fill(Int(origin), length(label))
    return members
end

function _train(cc::ClusterCard, t, id_var::AbstractPrimaryKey)
    X = stack(Fix1(getindex, t), cc.inputs, dims = 1)
    weights = isnothing(cc.weights) ? nothing : t[cc.weights]
    res = cc.method(X; weights)
    label = _labels(res)
    return (;
        members = _member_table(cc, t, id_var, label, 1),
        diagnostics = _diagnostics(cc.method, res),
        iteration = 1,
        # labels are never reissued, so this must be the highest ever seen and
        # not the highest currently present: a cluster dropped by `memory`
        # must not lend its number to an unrelated one
        highest_label = maximum(label; init = 0),
    )
end

"""
    _relabel_map(new_label, old_label, threshold, highest)

Which stored label each refit cluster should carry, and the highest label issued
once fresh ones are handed out.

`old_label` covers the rows the stored fit had seen, aligned with the first
`length(old_label)` entries of `new_label`. Noise (0) is not a cluster and takes
no part in the correspondence. For each refit cluster, the stored cluster
contributing most of its previously-labelled rows wins the label, provided that
share reaches `threshold`; otherwise the cluster is an emergence and takes a
fresh label. When several refit clusters claim the same stored one — a split —
the largest keeps the label and the rest are fresh.

Every scan runs in sorted order, so ties resolve to the lowest label rather than
to whatever a `Dict` happened to iterate first: the result must depend on the
data alone.
"""
function _relabel_map(new_label, old_label, threshold::Real, highest::Integer)
    shared = min(length(old_label), length(new_label))
    counts = Dict{Tuple{Int, Int}, Int}()   # (stored, refit) => shared rows
    labelled = Dict{Int, Int}()             # refit cluster => its previously-labelled rows
    @inbounds for i in 1:shared
        o, n = old_label[i], new_label[i]
        (o > 0 && n > 0) || continue
        counts[(o, n)] = get(counts, (o, n), 0) + 1
        labelled[n] = get(labelled, n, 0) + 1
    end

    stored = sort!(unique(o for o in old_label if o > 0))
    refit = sort!(unique(n for n in new_label if n > 0))

    claim = Dict{Int, Int}()                # refit cluster => stored cluster it claims
    for n in refit
        best_o, best_c = 0, 0
        for o in stored                     # sorted: ties go to the lowest stored label
            c = get(counts, (o, n), 0)
            c > best_c && ((best_o, best_c) = (o, c))
        end
        best_o > 0 && best_c >= threshold * labelled[n] && (claim[n] = best_o)
    end

    keeper = Dict{Int, Int}()               # stored cluster => refit cluster keeping it
    for n in refit                          # sorted: ties go to the lowest refit label
        o = get(claim, n, 0)
        o > 0 || continue
        held = get(keeper, o, 0)
        (held == 0 || counts[(o, n)] > counts[(o, held)]) && (keeper[o] = n)
    end

    map = Dict{Int, Int}(0 => 0)            # noise stays noise
    next = Int(highest)
    for n in refit
        o = get(claim, n, 0)
        if o > 0 && keeper[o] == n
            map[n] = o
        else
            next += 1
            map[n] = next
        end
    end
    return map, next
end

# Rows of `t` the stored model has not seen. Order is `t`'s own, so the refit
# input is deterministic.
function _fresh_rows(members, t, id_var::AbstractPrimaryKey)
    known = Set(members[id_var])
    ids = t[id_var]
    return [j for j in eachindex(ids) if !(ids[j] in known)]
end

function _refit_input(cc::ClusterCard, members, t, fresh)
    stored = stack(Fix1(getindex, members), cc.inputs, dims = 1)
    X = isempty(fresh) ? stored :
        hcat(stored, stack(col -> t[col][fresh], cc.inputs, dims = 1))
    weights = if isnothing(cc.weights)
        nothing
    else
        vcat(members[cc.weights], t[cc.weights][fresh])
    end
    return X, weights
end

function (cc::ClusterCard)(model, t, id_var::AbstractPrimaryKey)
    (; members) = model
    fresh = _fresh_rows(members, t, id_var)
    X, weights = _refit_input(cc, members, t, fresh)
    new_label = _labels(cc.method(X; weights))

    map, highest = _relabel_map(new_label, members[MEMBER_LABEL], cc.threshold, model.highest_label)
    relabelled = [map[n] for n in new_label]

    ids = vcat(members[id_var], t[id_var][fresh])
    position = Dict(id => i for (i, id) in enumerate(ids))
    labels = [relabelled[position[id]] for id in t[id_var]]
    prediction = SimpleTable(id_var => t[id_var], cc.output => labels)

    # Rolling forward on rows the model already had would spend an iteration
    # without growing anything, and `memory` counts iterations — so an
    # evaluation that adds nothing leaves the state alone and stays idempotent.
    (cc.lineage && !isempty(fresh)) || return prediction
    return prediction, CardState(
        content = jldserialize(_roll_forward(cc, model, t, fresh, ids, relabelled, highest, id_var))
    )
end

"""
    _roll_forward(cc, model, t, fresh, ids, relabelled, highest, id_var)

The state after a lineage-enabled evaluation: the stored members plus the rows
this evaluation added, all carrying their reconciled labels. New rows are stamped
with the new iteration, and `memory` drops members from iterations too old to
keep. `highest_label` only ever grows, so a label freed by `memory` is not
reissued.
"""
function _roll_forward(
        cc::ClusterCard, model, t, fresh, ids, relabelled, highest::Integer,
        id_var::AbstractPrimaryKey
    )
    (; members) = model
    iteration = model.iteration + 1
    origin = vcat(members[MEMBER_ORIGIN], fill(iteration, length(fresh)))

    rolled = SimpleTable()
    rolled[id_var] = ids
    for col in _member_columns(cc, id_var)
        col == id_var && continue
        rolled[col] = vcat(members[col], t[col][fresh])
    end
    rolled[MEMBER_LABEL] = relabelled
    rolled[MEMBER_ORIGIN] = origin

    if !isnothing(cc.memory)
        keep = findall(>=(iteration - cc.memory + 1), origin)
        for (col, v) in rolled
            rolled[col] = v[keep]
        end
    end

    return (;
        members = rolled,
        model.diagnostics,
        iteration,
        highest_label = highest,
    )
end

## UI representation

function CardWidget(
        ::Type{ClusterCard}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    )

    config = CardWidgetConfigs(parse_toml_config("config", key))
    c = combine_options(config.widget_configs; global_options, user_options)

    methods = collect(keys(CLUSTERING_METHODS))
    support_weights = ["kmeans"]

    fields = vcat(
        [
            Widget("inputs", c),
            Widget("method", c, options = methods),
        ],
        method_dependent_widgets(c, "method", config.methods),
        [
            Widget("weights", c, visible = "method" => support_weights, required = false),
            Widget("partition", c, required = false),
            Widget("output", c),
        ]
    )

    return CardWidget(key, fields, OutputSpec("output"))
end
