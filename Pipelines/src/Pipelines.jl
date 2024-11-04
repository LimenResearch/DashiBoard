module Pipelines

using Tables: Tables
using DBInterface: DBInterface
using OrderedCollections: OrderedDict
using DataIngestion: Repository, get_catalog

using FunSQL: pack,
    reflect,
    render,
    SQLNode,
    SQLClause,
    Partition,
    Define,
    Agg,
    Fun,
    Get,
    Var,
    Limit,
    Select,
    From,
    Where,
    Order,
    Group

include("tables.jl")
include("card.jl")

include("cards/partition.jl")

end
