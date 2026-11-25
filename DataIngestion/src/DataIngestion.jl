module DataIngestion

export Filter, ListFilter, IntervalFilter

public is_supported, acceptable_paths, data_path, load_files, summarize, VariableSummary, select, selection_query

using Base.ScopedValues: @with, ScopedValue
using Dates: Date, Time, DateTime

using FunSQL: SQLNode,
    Agg,
    Fun,
    Get,
    Var,
    Lit,
    Limit,
    Select,
    From,
    Where,
    Order,
    Group

using DBInterface: DBInterface
using DuckDBUtils: DuckDBUtils, Repository, SQLMacro, replace_table, to_sql
using DashiBase: @constructible, join_names, StringDict, Maybe
using IntervalSets: ClosedInterval, leftendpoint, rightendpoint
using Tables: Tables

const DATA_DIR = ScopedValue(".")

include("readers/utils.jl")
include("readers/csv.jl")
include("readers/json.jl")
include("readers/parquet.jl")

include("load.jl")
include("filters.jl")
include("summary.jl")

end
