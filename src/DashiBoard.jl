module DashiBoard

public launch

using Base.ScopedValues: @with

using HTTP: HTTP, startwrite, closewrite

using Oxygen: json, @post, @stream, serve

using Scratch: @get_scratch!

using JSON3: JSON3

using JSONTables: arraytable

using DBInterface: DBInterface

using Tables: Tables

using DuckDBUtils: Repository

using DataIngestion: is_supported, get_filter, stream_table, DataIngestion

using Pipelines: get_card, to_config, Pipelines

const cache_directory() = @get_scratch!("cache")

# TODO: allow db to live in other folders
const REPOSITORY = Ref{Repository}()

include("launch.jl")

function __init__()
    cache = cache_directory()
    REPOSITORY[] = Repository(joinpath(cache, "db.duckdb"))
end

end
