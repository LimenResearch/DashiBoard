module StreamlinerCore

export Model, Training, Data, AbstractData, DataPartition, default_parser
export get_templates, get_metadata, stream
export finetune, train, loadmodel, validate, evaluate, summarize

public has_weights

using Base: Fix1, Fix2, front, tail
using Statistics: mean, std
using Random: AbstractRNG, Xoshiro, seed!
using TOML: TOML
using EasyConfig: Config
using Dates: now, DateTime
using Tables: Tables
using NNlib: upsample_linear, upsample_nearest
using Flux: Dense, RNN, LSTM, GRU, Conv, ConvTranspose, MaxPool, MeanPool
using Flux: @layer, withgradient, destructure, loadmodel!, Losses, Flux
using MLUtils: numobs, obsview, flatten, group_indices, randn_like, DataLoader, MLUtils
using ParameterSchedulers: ParameterSchedulers as PS
using ProgressLogging: @withprogress, @logprogress
using ChainRulesCore: AbstractZero, NoTangent, unthunk, ChainRulesCore

using Optim: AbstractOptimizer, BFGS, LBFGS, Optim
using Optimisers: trainables,
    adjust!,
    update!,
    AbstractRule,
    Descent,
    Momentum,
    Nesterov,
    RMSProp,
    Adam,
    RAdam,
    AdaMax,
    ADAGrad,
    ADADelta,
    AMSGrad,
    NAdam,
    AdamW,
    OAdam,
    AdaBelief

using Base.ScopedValues: @with, ScopedValue
using EnumX: @enumx
using Primes: factor
using BSON: bson, load
using Printf: @sprintf
using UUIDs: uuid4, UUID

include("utils.jl")
include("variables.jl")
include("parser.jl")
include("data.jl")

include("model/formats.jl")
include("model/chain.jl")
include("model/architecture.jl")
include("model/metrics.jl")
include("model/regularizations.jl")
include("model/model.jl")

include("architectures/basic.jl")
include("architectures/vae.jl")

include("layers/affine.jl")
include("layers/byslice.jl")
include("layers/pooling.jl")

include("training/schedules.jl")
include("training/stoppers.jl")
include("training/optimizer.jl")
include("training/training.jl")

include("interface/result.jl")
include("interface/train.jl")
include("interface/load.jl")
include("interface/validate.jl")
include("interface/evaluate.jl")
include("interface/summarize.jl")

include("defaults.jl")

end