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

struct Metric{L, names, types}
    loss::L
    params::NamedTuple{names, types}
end

(m::Metric)(r) = m.loss(r.prediction, r.target; m.params...)

metricname(m::Metric) = nameof(m.loss)

# Parsing

get_loss(metadata::AbstractDict) = get_metric(metadata["loss"])

function get_metric(metric_metadata::AbstractDict)
    params = make(SymbolDict, metric_metadata)
    name = pop!(params, :name)
    agg_name = pop!(params, :agg, "mean")

    metric = PARSER[].metrics[name]
    agg = PARSER[].aggregators[agg_name]

    return metric(; agg, params...)
end

function get_metrics(metadata::AbstractDict)
    metric_metadatas = get_configs(metadata, "metrics")
    return Tuple(get_metric.(metric_metadatas))
end

# Accuracy of classifier

function accuracy(ŷ, y; agg = mean, dims = 1)
    ŷₘ = map(c -> Tuple(c)[dims], argmax(ŷ; dims))
    yₘ = map(c -> Tuple(c)[dims], argmax(y; dims))
    return agg(ŷₘ .== yₘ)
end

# Loss functions

Accuracy(; params...) = Metric(accuracy, values(params))

MAE(; params...) = Metric(Losses.mae, values(params))
MSE(; params...) = Metric(Losses.mse, values(params))
MSLE(; params...) = Metric(Losses.msle, values(params))
HuberLoss(; params...) = Metric(Losses.huber_loss, values(params))
LabelSmoothing(; params...) = Metric(Losses.label_smoothing, values(params))
CrossEntropy(; params...) = Metric(Losses.crossentropy, values(params))
LogitCrossEntropy(; params...) = Metric(Losses.logitcrossentropy, values(params))
BinaryCrossEntropy(; params...) = Metric(Losses.binarycrossentropy, values(params))
LogitBinaryCrossEntropy(; params...) = Metric(Losses.logitbinarycrossentropy, values(params))
KLDivergence(; params...) = Metric(Losses.kldivergence, values(params))
PoissonLoss(; params...) = Metric(Losses.poisson_loss, values(params))
HingeLoss(; params...) = Metric(Losses.hinge_loss, values(params))
SquaredHingeLoss(; params...) = Metric(Losses.squared_hinge_loss, values(params))
FocalLoss(; params...) = Metric(Losses.focal_loss, values(params))
BinaryFocalLoss(; params...) = Metric(Losses.binary_focal_loss, values(params))
SiameseContrastiveLoss(; params...) = Metric(Losses.siamese_contrastive_loss, values(params))

# TODO: PR to Flux to support `agg` for `dice_coeff_loss` and `tversky_loss`
