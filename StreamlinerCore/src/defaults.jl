const DEFAULT_PARSER = let

    models = StringDict(
        "basic" => basic,
        "vae" => vae,
    )

    # layer function returns format description and constructor
    layers = StringDict(
        "softmax" => softmax,
        "logsoftmax" => logsoftmax,
        "logsumexp" => logsumexp,
        "dense" => dense,
        "rnn" => rnn,
        "lstm" => lstm,
        "gru" => gru,
        "conv" => conv,
        "conv_t" => conv_t,
        "maxpool" => maxpool,
        "meanpool" => meanpool,
        "upsample" => upsample,
        "selector" => selector,
    )

    sigmas = StringDict(
        "" => identity,
        "identity" => identity,
        "celu" => Flux.celu,
        "elu" => Flux.elu,
        "gelu" => Flux.gelu,
        "hardsigmoid" => Flux.hardsigmoid,
        "hardtanh" => Flux.hardtanh,
        "leakyrelu" => Flux.leakyrelu,
        "lisht" => Flux.lisht,
        "logcosh" => Flux.logcosh,
        "logsigmoid" => Flux.logsigmoid,
        "relu" => Flux.relu,
        "relu6" => Flux.relu6,
        "rrelu" => Flux.rrelu,
        "selu" => Flux.selu,
        "sigmoid" => Flux.sigmoid,
        "softplus" => Flux.softplus,
        "softshrink" => Flux.softshrink,
        "softsign" => Flux.softsign,
        "swish" => Flux.swish,
        "tanh" => tanh,
        "tanhshrink" => Flux.tanhshrink,
        "trelu" => Flux.trelu,
    )

    aggregators = StringDict(
        "mean" => mean,
        "sum" => sum,
    )

    metrics = StringDict(
        "accuracy" => Accuracy,
        "mae" => MAE,
        "mse" => MSE,
        "msle" => MSLE,
        "huber_loss" => HuberLoss,
        "label_smoothing" => LabelSmoothing,
        "crossentropy" => CrossEntropy,
        "logitcrossentropy" => LogitCrossEntropy,
        "binarycrossentropy" => BinaryCrossEntropy,
        "logitbinarycrossentropy" => LogitBinaryCrossEntropy,
        "kldivergence" => KLDivergence,
        "poisson_loss" => PoissonLoss,
        "hinge_loss" => HingeLoss,
        "squared_hinge_loss" => SquaredHingeLoss,
        "binary_focal_loss" => FocalLoss,
        "focal_loss" => BinaryFocalLoss,
        "siamese_contrastive_loss" => SiameseContrastiveLoss,
        "vae_loss" => VAELoss,
        # These losses do not yet support `agg` TODO PR to Flux to amend this
        # "dice_coeff_loss"        => Metric(Losses.dice_coeff_loss),
        # "tversky_loss"           => Metric(Losses.tversky_loss),
    )

    regularizations = StringDict(
        "l1" => l1,
        "l2" => l2,
    )

    optimizers = StringDict(
        "Descent" => Descent,
        "Momentum" => Momentum,
        "Nesterov" => Nesterov,
        "RMSProp" => RMSProp,
        "Adam" => Adam,
        "RAdam" => RAdam,
        "AdaMax" => AdaMax,
        "ADAGrad" => ADAGrad,
        "ADADelta" => ADADelta,
        "AMSGrad" => AMSGrad,
        "NAdam" => NAdam,
        "AdamW" => AdamW,
        "OAdam" => OAdam,
        "AdaBelief" => AdaBelief,
        "BFGS" => BFGS,
        "LBFGS" => LBFGS,
    )

    schedules = StringDict(
        "Step" => PS.Step,
        "Exp" => PS.Exp,
        "Poly" => PS.Poly,
        "Inv" => PS.Inv,
        "Triangle" => PS.Triangle,
        "TriangleDecay2" => PS.TriangleDecay2,
        "TriangleExp" => PS.TriangleExp,
        "Sin" => PS.Sin,
        "SinDecay2" => PS.SinDecay2,
        "SinExp" => PS.SinExp,
        "CosAnneal" => PS.CosAnneal,
    )

    stoppers = StringDict(
        "early_stopping" => Flux.early_stopping,
        "plateau" => Flux.plateau,
    )

    devices = StringDict(
        "cpu" => Flux.cpu,
        "gpu" => Flux.gpu,
        "f32" => Flux.f32,
        "f64" => Flux.f64,
    )

    Parser(;
        models,
        layers,
        sigmas,
        aggregators,
        metrics,
        regularizations,
        optimizers,
        schedules,
        stoppers,
        devices,
    )

end

const PARSER = ScopedValue{Parser}(DEFAULT_PARSER)

"""
    default_parser(; plugins::AbstractVector{Parser}=Parser[])

Return a `parser::`[`Parser`](@ref) object that includes StreamlinerCore defaults
together with optional `plugins`.
"""
function default_parser(; plugins::AbstractVector{Parser} = Parser[])
    return foldl(combine!, plugins, init = copy(DEFAULT_PARSER))
end
