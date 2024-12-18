module Pipelines

export Cards

export RescaleCard, SplitCard

public plan, evaluate, deevaluate

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
    From,
    LeftJoin

using Graphs: DiGraph, add_edge!, topological_sort, inneighbors

using StatsModels: Term, ConstantTerm
using StatsAPI: predict
using GLM: glm,
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
