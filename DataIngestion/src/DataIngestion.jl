module DataIngestion

export Experiment, Partition, register_partition

using FunSQL: pack,
    reflect,
    render,
    SQLNode,
    Fun,
    Agg,
    Get,
    Var,
    Select,
    From,
    Where,
    Group,
    Partition,
    Define
using DuckDB: DBInterface, DuckDB
using ConcurrentUtilities: Pool, acquire, release
using IntervalSets: ClosedInterval, leftendpoint, rightendpoint
using IterTools: flagfirst
using Tables: Tables

include("repository.jl")
include("experiment.jl")
include("partition.jl")
include("query.jl")
include("filters.jl")
include("summary.jl")

end
