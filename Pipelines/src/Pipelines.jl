module Pipelines

export Cards

using Tables: Tables
using DBInterface: DBInterface
using UUIDs: uuid4
using OrderedCollections: OrderedDict
using DataIngestion: Repository, get_catalog

using FunSQL: render,
    SQLClause,
    SQLNode,
    SQLCatalog,
    Partition,
    Agg,
    Fun,
    Get,
    Select,
    From

using Graphs: DiGraph, add_edge!, topological_sort, inneighbors

include("utils.jl")
include("tables.jl")
include("card.jl")

include("cards/partition.jl")

include("pipeline.jl")

end
