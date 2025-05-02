module Pipelines

export card_configurations, get_card

export AbstractCard,
    SplitCard,
    RescaleCard,
    ClusterCard,
    DimensionalityReductionCard,
    GLMCard,
    InterpCard,
    GaussianEncodingCard,
    StreamlinerCard

public train, evaluate, deevaluate, inputs, outputs, invertible

public evaluatenodes, deevaluatenodes, visualize, Node

public to_config, default_parser, PARSER, MODEL_DIR, TRAINING_DIR

using Base: Fix1, Fix2
using Base.ScopedValues: @with, ScopedValue

using UUIDs: uuid4

using TOML: parsefile
using RelocatableFolders: @path

using JLD2: jldopen
using StructTypes: constructfrom

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
    colnames

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

using Graphs: DiGraph, add_edge!, topological_sort, inneighbors

using StatsModels: terms, termnames, Term, ConstantTerm, FormulaTerm

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
    to_config,
    get_rng

using Clustering: assignments, kmeans, dbscan

using MultivariateStats: PCA, PPCA, FactorAnalysis, MDS

using MLDataDevices: DeviceIterator
using MultivariateStats: PCA, PPCA, FactorAnalysis, MDS

using Dates: hour, minute

const WIDGET_CONFIG = ScopedValue{Dict{String, Any}}()

function parse_toml_config(args...)
    fs..., l = args
    path = @path joinpath(@__DIR__, "..", "assets", fs..., string(l, ".toml"))
    return parsefile(path)
end

include("tables.jl")
include("widgets.jl")
include("utils.jl")

include("funnels/onehot.jl")
include("funnels/basic.jl")

include("card.jl")

include("cards/split.jl")
include("cards/rescale.jl")
include("cards/cluster.jl")
include("cards/dimensionality_reduction.jl")
include("cards/glm.jl")
include("cards/interp.jl")
include("cards/gaussian_encoding.jl")
include("cards/streamliner.jl")

include("pipeline.jl")

end
