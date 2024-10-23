module DataIngestion

export Experiment, Partition, register_partition

using FunSQL: pack, reflect, render, SQLNode, Fun, Get, Var, Select, From, Where
using DuckDB: DBInterface, DuckDB
using ConcurrentUtilities: Pool, acquire, release
using IntervalSets: Interval, leftendpoint, rightendpoint, isleftclosed, isrightclosed
using IterTools: flagfirst
using Tables: Tables

include("repository.jl")
include("experiment.jl")
include("partition.jl")
include("query.jl")
include("filters.jl")
include("summary.jl")

end
