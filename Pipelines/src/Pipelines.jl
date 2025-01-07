module Pipelines

export get_card, AbstractCard, RescaleCard, SplitCard

public train, evaluate, deevaluate

using Tables: Tables
using DBInterface: DBInterface
using DuckDBUtils: Repository,
    get_catalog,
    with_connection,
    with_table,
    load_table,
    replace_table,
    colnames

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
    LeftJoin

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

include("tables.jl")
include("card.jl")

include("cards/split.jl")
include("cards/rescale.jl")
include("cards/glm.jl")

include("pipeline.jl")

end
