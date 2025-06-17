module DashiBoard

public launch

using Base: Fix1, Fix2

using Base.ScopedValues: with

using HTTP: HTTP, startwrite

using Scratch: @get_scratch!

using JSON: JSON

using DBInterface: DBInterface

using Tables: Tables

using DuckDBUtils: Repository

using DataIngestion: is_supported, export_table, Filter, DataIngestion

using Pipelines: get_card, get_state, Pipelines

import AlgebraOfGraphics, CairoMakie

const cache_directory() = @get_scratch!("cache")

# TODO: allow db to live in other folders
const REPOSITORY = Ref{Repository}()

include("middleware.jl")
include("launch.jl")

function __init__()
    cache = cache_directory()
    REPOSITORY[] = Repository(joinpath(cache, "db.duckdb"))
    return
end

end
