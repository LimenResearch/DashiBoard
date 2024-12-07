module Pipelines

export Cards

export RescaleCard, SplitCard

public evaluate

using Tables: Tables
using DBInterface: DBInterface
using UUIDs: uuid4
using OrderedCollections: OrderedDict
using DuckDBUtils: Repository, get_catalog

using FunSQL: render,
    SQLClause,
    SQLNode,
    SQLCatalog,
    Partition,
    Agg,
    Fun,
    Get,
    Define,
    From

using Graphs: DiGraph, add_edge!, topological_sort, inneighbors

include("utils.jl")
include("tables.jl")
include("card.jl")

include("cards/split.jl")
include("cards/rescale.jl")

include("pipeline.jl")

end
