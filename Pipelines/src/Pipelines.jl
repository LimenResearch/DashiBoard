module Pipelines

using Tables: Tables
using DBInterface: DBInterface
using UUIDs: uuid4
using OrderedCollections: OrderedDict
using DataIngestion: Repository, get_catalog

using FunSQL: render,
    SQLClause,
    Partition,
    Agg,
    Fun,
    Get,
    Select,
    From

include("tables.jl")
include("card.jl")

include("cards/partition.jl")

end
