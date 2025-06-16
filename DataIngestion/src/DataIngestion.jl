module DataIngestion

export get_filter, AbstractFilter, ListFilter, IntervalFilter

public is_supported, get_files, load_files, summarize, select, export_table

using FunSQL: SQLNode,
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
using DuckDBUtils: Repository, get_catalog, replace_table, to_sql, in_schema
using IntervalSets: ClosedInterval, leftendpoint, rightendpoint
using IterTools: flagfirst
using Tables: Tables

include("readers/utils.jl")
include("readers/csv.jl")
include("readers/json.jl")
include("readers/parquet.jl")

include("load.jl")
include("filters.jl")
include("summary.jl")

end
