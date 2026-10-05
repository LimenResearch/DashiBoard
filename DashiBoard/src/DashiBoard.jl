module DashiBoard

public launch

using Base: Fix1, Fix2

using Base.ScopedValues: @with, ScopedValue

using HTTP: HTTP, startread, startwrite, closeread

using Dates: Dates

using Scratch: @get_scratch!

using JSON: JSON

# TOML is Pipelines' native configuration format, so a cards document written by hand is as
# likely to be TOML as JSON; the file routes read both (handlers.jl, `parse_document`).
using TOML: TOML

# For naming the members of a loop (handlers.jl, `loop_issues`): Graphs' own error for a cyclic
# dependency graph says only that there is one, and a client cannot act on that.
using Graphs: strongly_connected_components, has_edge, gdistances

using DBInterface: DBInterface

using Tables: Tables

using FunSQL: SQLNode,
    From,
    Limit,
    Group,
    Select,
    Define,
    Partition,
    Agg,
    Order,
    Get,
    Asc,
    Desc,
    # `Fun` for `finite_projection`'s `CASE WHEN isfinite(col) THEN col END` (handlers.jl): the
    # projection is built as FunSQL nodes, so the SQL function call needs `Fun` in scope here.
    Fun

using DuckDBUtils: Repository, export_table, to_nrow, colnames

# `finite_projection` (handlers.jl) reads a table's column types out of `information_schema`, and
# the cheapest way to consume that result is the same `DataFrame` the test suite already builds
# results with. `DataFrames` is a DashiBoard dependency already — brought into scope here rather
# than adding a new one.
using DataFrames: DataFrame

using DataIngestion: Filter, DataIngestion

using Pipelines: Card, get_state, Pipelines

# load the PipelinesMakie extension
import AlgebraOfGraphics, CairoMakie

const cache_directory() = @get_scratch!("cache")

const REPOSITORY = Ref{Repository}()

const ID_VAR = ScopedValue("_id")

# The directory every file route is confined to, and the two kinds of file Pipelines has no
# directory for. The tables' and the configurations' directories are DataIngestion's and
# Pipelines' own scoped values; these complete the set.
const WORKSPACE = ScopedValue("")
const PIPELINE_DIR = ScopedValue("")
const FILTER_DIR = ScopedValue("")

# The extensions the server was launched with — each name and where it is, as the workspace
# file says — and which of them contributed each registry entry (`"model:fuzzy"`,
# `"funnel:time"`, `"loader:x"`, `"transform:y"`). Filled by the launcher; what lets a pipeline's
# download name exactly the extensions it needs.
const EXTENSIONS = ScopedValue(Dict{String, Any}())
const EXTENSION_OF = ScopedValue(Dict{String, String}())

include("workspace.jl")
include("handlers.jl")
include("bundle.jl")
include("middleware.jl")
include("launch.jl")

function __init__()
    # DuckDB is single-writer, and the scratchspace path is fixed per package — so every
    # DashiBoard process contends for one file, and the test suite is just another process:
    # running it while a server is up fails at load with "Conflicting lock is held".
    # `DASHIBOARD_CACHE` lets a caller opt out; the default is unchanged.
    cache = get(ENV, "DASHIBOARD_CACHE", cache_directory())
    mkpath(cache)
    REPOSITORY[] = Repository(joinpath(cache, "db.duckdb"))
    return
end

end
