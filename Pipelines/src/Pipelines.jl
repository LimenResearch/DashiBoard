module Pipelines

export Card,
    SplitCard,
    WindowFunctionCard,
    RescaleCard,
    ClusterCard,
    DimensionalityReductionCard,
    GLMCard,
    MixedModelCard,
    InterpCard,
    GaussianEncodingCard,
    StreamlinerCard,
    WildCard

public get_metadata, register_card, CardSpec, card_widgets

public register_wild_card, WildCardSettings

public SourceVariables, OutputVariables, get_node_inputs, get_node_outputs

public train!, evaljoin, train_evaljoin!

public train, evaluate, inputs, outputs, invertible

public report, visualize, get_card, get_state, invert, Node

public default_parser, PARSER, MODEL_DIR, TRAINING_DIR

using Base: Fix1, Fix2, AbstractLock
using Base.ScopedValues: ScopedValue

using TOML: parsefile
using RelocatableFolders: @path

using JLD2: jldopen
using StructUtils: @choosetype, @nonstruct, @kwarg, @tags, fieldtags, fielddefaults, StructUtils

using OrderedCollections: OrderedDict, OrderedSet
using Tables: Tables
using DBInterface: DBInterface

using DuckDBUtils: DuckDBUtils,
    Repository,
    in_schema,
    render_params,
    get_catalog,
    with_table,
    load_table,
    replace_table,
    delete_table,
    with_table_name,
    with_table_names,
    colnames,
    to_nrow

using FunSQL:
    render,
    SQLNode,
    SQLCatalog,
    Partition,
    Group,
    AggClosure,
    Agg,
    Fun,
    Lit,
    Get,
    Var,
    Select,
    Order,
    Where,
    From,
    LeftJoin,
    Join

using Graphs: SimpleDiGraphFromIterator, DiGraph, Edge,
    inneighbors, outneighbors, nv, add_vertices!, topological_sort

using StatsModels: term, terms, termnames,
    ConstantTerm, Term, InteractionTerm, FormulaTerm, AbstractTerm

using StatsAPI: fit, predict, modelmatrix, RegressionModel

using StatsBase: fweights, median

using Distributions: Distribution,
    Normal,
    Binomial,
    Gamma,
    InverseGaussian,
    Poisson

using GLM:
    LinearModel,
    GeneralizedLinearModel,
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

using StreamlinerCore:
    AbstractData,
    FunneledData,
    Funnel,
    Model,
    Streaming,
    Training,
    Template,
    Parser,
    default_parser,
    PARSER,
    metricname,
    get_rng,
    StreamlinerCore as SC

using Clustering: assignments, kmeans, dbscan, affinityprop

using Distances: pairwise, SqEuclidean, Euclidean, Cityblock, WeightedCityblock, Minkowski

using LinearAlgebra: diagind

using MultivariateStats: PCA, PPCA, FactorAnalysis, MDS

using Dates: hour, minute

const StringDict = Dict{String, Any}
const SymbolDict = Dict{Symbol, Any}

# Alias to potentially support richer primary keys in the future
const AbstractPrimaryKey = AbstractString
const PrimaryKey = String

function parse_toml_config(args...)::StringDict
    fs..., l = args
    path = @path joinpath(@__DIR__, "..", "assets", fs..., string(l, ".toml"))
    return parsefile(path)
end

include("tables.jl")
include("widgets.jl")
include("utils.jl")
include("schema.jl")
include("dict_helpers.jl")
include("card.jl")
include("method.jl")
include("dissimilarities.jl")

include("cards/standard.jl")
include("cards/split.jl")
include("cards/window_function.jl")
include("cards/rescale.jl")
include("cards/cluster.jl")
include("cards/dimensionality_reduction.jl")
include("cards/glm.jl")
include("cards/interp.jl")
include("cards/gaussian_encoding.jl")
include("cards/streamliner.jl")
include("cards/wild.jl")

include("node.jl")
include("dag.jl")
include("pipeline.jl")

include("group_api/deps.jl")
include("group_api/dag.jl")
include("group_api/schema.jl")

function __init__()
    register_card("split" => CardSpec(SplitCard, "Split"))
    register_card("window_function" => CardSpec(WindowFunctionCard, "Window Function"))
    register_card("rescale" => CardSpec(RescaleCard, "Rescale"))
    register_card("cluster" => CardSpec(ClusterCard, "Cluster"))
    register_card("dimensionality_reduction" => CardSpec(DimensionalityReductionCard, "Dimensionality Reduction"))
    register_card("glm" => CardSpec(GLMCard, "GLM"))
    register_card("interp" => CardSpec(InterpCard, "Interpolation"))
    register_card("gaussian_encoding" => CardSpec(GaussianEncodingCard, "Gaussian Encoding"))
    register_card("streamliner" => CardSpec(StreamlinerCard, "Streamliner"))
    return
end

end
