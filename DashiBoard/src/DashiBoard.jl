module DashiBoard

public launch

using Base: Fix1, Fix2

using Base.ScopedValues: @with

using HTTP: HTTP, startwrite

using Scratch: @get_scratch!

using JSON: JSON

using DBInterface: DBInterface

using Tables: Tables

using FunSQL: SQLNode,
    From,
    Limit,
    Group,
    Select,
    Agg,
    Order,
    Get,
    Asc,
    Desc

using DuckDBUtils: Repository, export_table, to_nrow, colnames

using DataIngestion: acceptable_paths, Filter, DataIngestion

using Pipelines: Card, get_state, Pipelines

import AlgebraOfGraphics, CairoMakie

const cache_directory() = @get_scratch!("cache")

# TODO: allow db to live in other folders
const REPOSITORY = Ref{Repository}()

include("settings.jl")
include("handlers.jl")
include("middleware.jl")
include("launch.jl")

function __init__()
    cache = cache_directory()
    REPOSITORY[] = Repository(joinpath(cache, "db.duckdb"))
    return
end

end
