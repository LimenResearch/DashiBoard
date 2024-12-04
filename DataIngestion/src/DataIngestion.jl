module DataIngestion

export Filters, ListFilter, IntervalFilter

public is_supported, load_files, summarize, select

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
using DuckDBUtils: Repository, get_catalog
using IntervalSets: ClosedInterval, leftendpoint, rightendpoint, :..
using IterTools: flagfirst
using Tables: Tables
using OrderedCollections: OrderedDict

include("load.jl")
include("filters.jl")
include("summary.jl")

end
