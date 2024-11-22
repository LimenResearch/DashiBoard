module DataIngestion

export Repository, Filters

public load_files, summarize, select

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
include("load.jl")
include("filters.jl")
include("summary.jl")

end
