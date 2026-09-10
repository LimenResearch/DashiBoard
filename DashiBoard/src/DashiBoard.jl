module DashiBoard

public launch

using Base: Fix1, Fix2

using Base.ScopedValues: @with, ScopedValue

using HTTP: HTTP, startread, startwrite, closeread

using Scratch: @get_scratch!

using JSON: JSON

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
    Desc

using DuckDBUtils: Repository, export_table, to_nrow, colnames

using DataIngestion: acceptable_paths, Filter, DataIngestion

using Pipelines: Card, get_state, Pipelines

# load the PipelinesMakie extension
import AlgebraOfGraphics, CairoMakie

const cache_directory() = @get_scratch!("cache")

const REPOSITORY = Ref{Repository}()

const ID_VAR = ScopedValue("_id")

include("handlers.jl")
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
