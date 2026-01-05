# Callable structure to evaluate parameters

struct Evaluator{R, D, L, T <: Tuple}
    re::R
    data::D
    loss::L
    regs::T
end

Evaluator(data, loss, regs::Tuple) = Evaluator(identity, data, loss, regs)

function (ev::Evaluator)(θ)
    (; re, data, loss, regs) = ev
    m = re(θ)
    output = m(data)
    l = loss(output)
    rs = map(Fix1(|>, m), regs)
    # Avoid empty `sum`
    objective = isempty(rs) ? l : l + sum(rs)
    return (; objective, loss = l, regularizations = rs, output)
end

# storage helper

compute_metric(m::Number, _) = m
compute_metric(m, res) = m(res)
compute_metric(ms::Tuple, res) = map(Fix2(compute_metric, res), ms)

function store_metrics!(fs, vs, res, i)
    foreach(fs, vs) do f, v
        v[i] = compute_metric(f, res)
    end
    return
end

function compute_metrics(fs, model, iter)
    vs = map(_ -> fill(NaN, length(iter)), fs)
    for (n, data) in enumerate(iter)
        res = model(data)
        store_metrics!(fs, vs, res, n)
    end
    return map(mean, vs)
end

# Convert `Flux` losses to `StreamlinerCore` metrics

struct Metric{M, names, types}
    metric::M
    params::NamedTuple{names, types}
end

Metric(metric; params...) = Metric(metric, values(params))

(m::Metric)(r) = m.metric(r.prediction, r.target; m.params...)

metricname(m::Metric) = nameof(m.metric)

# Parsing

parse_loss(metadata::AbstractDict) = parse_metric(metadata["loss"])

function parse_metric(metric_metadata::AbstractDict)
    params = make(SymbolDict, metric_metadata)
    name = pop!(params, :name)
    agg_name = pop!(params, :agg, "mean")

    metric = PARSER[].metrics[name]
    agg = PARSER[].aggregators[agg_name]

    return metric(; agg, params...)
end

function parse_metrics(metadata::AbstractDict)
    metric_metadatas = get_configs(metadata, "metrics")
    return Tuple(parse_metric.(metric_metadatas))
end

# Accuracy of classifier

function accuracy(ŷ, y; agg = mean, dims = 1)
    ŷₘ = map(c -> Tuple(c)[dims], argmax(ŷ; dims))
    yₘ = map(c -> Tuple(c)[dims], argmax(y; dims))
    return agg(ŷₘ .== yₘ)
end

# Loss functions

Accuracy(; params...) = Metric(accuracy; params...)

MAE(; params...) = Metric(Losses.mae; params...)
MSE(; params...) = Metric(Losses.mse; params...)
MSLE(; params...) = Metric(Losses.msle; params...)
HuberLoss(; params...) = Metric(Losses.huber_loss; params...)
LabelSmoothing(; params...) = Metric(Losses.label_smoothing; params...)
CrossEntropy(; params...) = Metric(Losses.crossentropy; params...)
LogitCrossEntropy(; params...) = Metric(Losses.logitcrossentropy; params...)
BinaryCrossEntropy(; params...) = Metric(Losses.binarycrossentropy; params...)
LogitBinaryCrossEntropy(; params...) = Metric(Losses.logitbinarycrossentropy; params...)
KLDivergence(; params...) = Metric(Losses.kldivergence; params...)
PoissonLoss(; params...) = Metric(Losses.poisson_loss; params...)
HingeLoss(; params...) = Metric(Losses.hinge_loss; params...)
SquaredHingeLoss(; params...) = Metric(Losses.squared_hinge_loss; params...)
FocalLoss(; params...) = Metric(Losses.focal_loss; params...)
BinaryFocalLoss(; params...) = Metric(Losses.binary_focal_loss; params...)
SiameseContrastiveLoss(; params...) = Metric(Losses.siamese_contrastive_loss; params...)
