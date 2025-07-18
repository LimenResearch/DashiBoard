module DataIngestion

export Filter, ListFilter, IntervalFilter

public is_supported, acceptable_paths, load_files, summarize, select

using Base.ScopedValues: @with, ScopedValue
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

const StringDict = Dict{String, Any}
const DATA_DIR = ScopedValue("")

include("readers/utils.jl")
include("readers/csv.jl")
include("readers/json.jl")
include("readers/parquet.jl")

include("load.jl")
include("filters.jl")
include("summary.jl")

end
