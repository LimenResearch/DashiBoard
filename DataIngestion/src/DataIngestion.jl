module DataIngestion

export get_filter, AbstractFilter, ListFilter, IntervalFilter, DateIntervalFilter, TimeIntervalFilter, DateTimeIntervalFilter

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
using DBInterface: DBInterface
using DuckDBUtils: Repository, get_catalog
using IntervalSets: ClosedInterval, leftendpoint, rightendpoint, :..
using IterTools: flagfirst
using Tables: Tables
using OrderedCollections: OrderedDict
using Dates

include("load.jl")
include("filters.jl")
include("summary.jl")

end
