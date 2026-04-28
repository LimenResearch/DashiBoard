module StreamlinerCore

export Result, Model, Data, AbstractData, DataPartition, Training, Streaming
export default_parser
export get_templates, get_metadata, get_nsamples
export stream, finetune, train, loadmodel, validate, evaluate, summarize

public instantiate, requires_shape, requires_format
public Parser, PARSER, MODEL_CONTEXT
public has_weights, output_path, stats_path, stats_tensor, metricname
public Shape, AbstractFormat, ClassicalFormat, FlatFormat, SpatialFormat
public Architecture, parse_modules, modules
public Metric
# funnels and funnel accessor functions
public RichColumn, colname, db_funnel, DBFunnel, Funnel
public get_helpers, get_order_by,
    get_inputs, get_constant_inputs, get_input_paths,
    get_targets, get_constant_targets, get_target_paths

using DuckDBUtils: DuckDBUtils,
    Repository,
    Batches,
    StreamResult

using Base: Fix1, Fix2, front, tail
using Statistics: mean, std
using Random: AbstractRNG, Xoshiro, seed!
using TOML: TOML
using Dates: now, DateTime
using StructUtils: make
using Tables: Tables
using NNlib: upsample_linear, upsample_nearest
using Flux: Dense, RNN, LSTM, GRU, Conv, ConvTranspose, MaxPool, MeanPool
using Flux: @layer, withgradient, destructure, loadmodel!, Losses, Flux
using MLUtils: numobs, obsview, flatten, group_indices, randn_like, DataLoader, MLUtils
using ParameterSchedulers: ParameterSchedulers as PS
using ProgressLogging: @withprogress, @logprogress
using ChainRulesCore: AbstractZero, NoTangent, unthunk, ChainRulesCore

using NLSolversBase: only_fg!
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
using JLD2: jldopen
using Printf: @sprintf

"""
    get_metadata(x)::Dict{String, Any}

Extract metadata for `x`.
`metadata` should be a dictionary of information that identifies `x` univoquely.
`get_metadata` has methods for [`Model`](@ref) and [`Training`](@ref).
"""
function get_metadata end

include("utils.jl")
include("variables.jl")
include("parser.jl")
include("data.jl")

include("funnel/transform.jl")
include("funnel/funnel.jl")
include("funnel/funneled_data.jl")
include("funnel/onehot.jl")

include("model/formats.jl")
include("model/chain.jl")
include("model/architecture.jl")
include("model/metrics.jl")
include("model/regularizations.jl")
include("model/model.jl")

include("architectures/basic.jl")
include("architectures/vae.jl")

include("layers/formatter.jl")
include("layers/affine.jl")
include("layers/byslice.jl")
include("layers/pooling.jl")
include("layers/selector.jl")

include("training/schedules.jl")
include("training/stoppers.jl")
include("training/optimizer.jl")
include("training/training.jl")

include("interface/train.jl")
include("interface/load.jl")
include("interface/validate.jl")
include("interface/evaluate.jl")
include("interface/summarize.jl")

include("defaults.jl")

end
