module Pipelines

export card_configurations, get_card, AbstractCard, RescaleCard, SplitCard, InterpCard, GaussianEncodingCard

public train, evaluate, deevaluate

using Base: Fix1, Fix2

using TOML: parsefile
using RelocatableFolders: @path

using OrderedCollections: OrderedDict, OrderedSet
using Tables: Tables
using DBInterface: DBInterface
using DuckDBUtils: Repository,
    get_catalog,
    with_connection,
    with_table,
    load_table,
    replace_table,
    colnames,
    uuid4

using FunSQL: render,
    SQLNode,
    SQLCatalog,
    Partition,
    Group,
    Agg,
    Fun,
    Get,
    Define,
    Select,
    Order,
    Where,
    From,
    LeftJoin,
    Join

using Graphs: DiGraph, add_edge!, topological_sort, inneighbors

using StatsModels: Term, ConstantTerm
using StatsAPI: fit, predict
using GLM: GeneralizedLinearModel,
    RegressionModel,
    canonicallink,
    Normal,
    Binomial,
    Gamma,
    InverseGaussian,
    Poisson,
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

const WIDGET_CONFIG = Ref{Dict{String, Any}}()

config_path(fn) = @path joinpath(@__DIR__, "..", "assets", fn)

include("tables.jl")
include("widgets.jl")
include("card.jl")

include("cards/split.jl")
include("cards/rescale.jl")
include("cards/glm.jl")
include("cards/interp.jl")
include("cards/gaussian.jl")


include("pipeline.jl")

function __init__()
    fns = ["general.toml", "split.toml", "glm.toml", "interp.toml"]
    init = Dict{String, Any}
    return WIDGET_CONFIG[] = mapfoldl(parsefile ∘ config_path, merge!, fns; init)
end

end
