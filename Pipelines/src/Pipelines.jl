module Pipelines

export card_type, card_widgets

export Card,
    SplitCard,
    RescaleCard,
    ClusterCard,
    DimensionalityReductionCard,
    GLMCard,
    InterpCard,
    GaussianEncodingCard,
    StreamlinerCard,
    WildCard

export register_card, CardConfig

public train!, evaljoin, train_evaljoin!

public train, evaluate, inputs, outputs, invertible

public report, visualize, get_card, get_state, invert, Node

public default_parser, PARSER, MODEL_DIR, TRAINING_DIR

using Base: Fix1, Fix2
using Base.ScopedValues: ScopedValue

using UUIDs: uuid4

using TOML: parsefile
using RelocatableFolders: @path

using JLD2: jldopen
using StructUtils: make

using OrderedCollections: OrderedDict, OrderedSet
using Tables: Tables
using DBInterface: DBInterface

using DuckDBUtils: DuckDBUtils,
    Repository,
    Batches,
    StreamResult,
    render_params,
    get_catalog,
    with_connection,
    with_table,
    load_table,
    replace_table,
    delete_table,
    colnames,
    to_nrow

using FunSQL: render,
    SQLNode,
    SQLCatalog,
    Partition,
    Group,
    Agg,
    Fun,
    Get,
    Var,
    Define,
    Select,
    Order,
    Where,
    Limit,
    From,
    LeftJoin,
    Join

using Graphs: SimpleDiGraphFromIterator, DiGraph, Edge,
    inneighbors, outneighbors, nv, topological_sort

using StatsModels: terms, termnames, Term, ConstantTerm, FormulaTerm, AbstractTerm

using StatsAPI: fit, predict, RegressionModel

using Distributions: Distribution,
    Normal,
    Binomial,
    Gamma,
    InverseGaussian,
    Poisson

using GLM: GeneralizedLinearModel,
    RegressionModel,
    canonicallink,
    Link,
    CauchitLink,
    CloglogLink,
    IdentityLink,
    InverseLink,
    InverseSquareLink,
    LogitLink,
    LogLink,
    NegativeBinomialLink,
    ProbitLink,
    SqrtLink

using DataInterpolations: ExtrapolationType,
    ConstantInterpolation,
    LinearInterpolation,
    QuadraticInterpolation,
    QuadraticSpline,
    CubicSpline,
    AkimaInterpolation,
    PCHIPInterpolation

using StreamlinerCore: StreamlinerCore,
    AbstractData,
    Model,
    Streaming,
    Training,
    Template,
    Parser,
    default_parser,
    PARSER,
    metricname,
    get_rng

using OneHotArrays: onehotbatch

using Clustering: assignments, kmeans, dbscan

using MultivariateStats: PCA, PPCA, FactorAnalysis, MDS

using Dates: hour, minute

const StringDict = Dict{String, Any}
const SymbolDict = Dict{Symbol, Any}

function parse_toml_config(args...)::StringDict
    fs..., l = args
    path = @path joinpath(@__DIR__, "..", "assets", fs..., string(l, ".toml"))
    return parsefile(path)
end

const WIDGET_TYPES = ScopedValue{StringDict}(parse_toml_config("widget_types"))

include("tables.jl")
include("widgets.jl")
include("utils.jl")

include("funnels/onehot.jl")
include("funnels/basic.jl")

include("card.jl")

include("cards/standard.jl")
include("cards/split.jl")
include("cards/rescale.jl")
include("cards/cluster.jl")
include("cards/dimensionality_reduction.jl")
include("cards/glm.jl")
include("cards/interp.jl")
include("cards/gaussian_encoding.jl")
include("cards/streamliner.jl")
include("cards/wild.jl")

include("pipeline.jl")
include("dag.jl")

function __init__()
    register_card(SPLIT_CARD_CONFIG)
    register_card(RESCALE_CARD_CONFIG)
    register_card(CLUSTER_CARD_CONFIG)
    register_card(DIMENSIONALITY_REDUCTION_CARD_CONFIG)
    register_card(GLM_CARD_CONFIG)
    register_card(INTERP_CARD_CONFIG)
    register_card(GAUSSIAN_ENCODING_CARD_CONFIG)
    register_card(STREAMLINER_CARD_CONFIG)
    return
end

end
