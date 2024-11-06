module DataIngestion

export with_experiment, Experiment, Filters

public init!, summarize, select

using FunSQL: pack,
    reflect,
    render,
    SQLNode,
    Fun,
    Get,
    Var,
    Limit,
    Select,
    From,
    Where,
    Order,
    Group
using DuckDB: DBInterface, DuckDB
using ConcurrentUtilities: Pool, acquire, release
using IntervalSets: ClosedInterval, leftendpoint, rightendpoint, :..
using IterTools: flagfirst
using Tables: Tables

include("repository.jl")
include("experiment.jl")
include("filters.jl")
include("summary.jl")

end
