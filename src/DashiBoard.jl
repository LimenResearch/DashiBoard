module DashiBoard

public launch

using Base.ScopedValues: @with

using HTTP: HTTP

using Oxygen: json, @post, serve

using Scratch: @get_scratch!

using JSON3: JSON3

using JSONTables: arraytable

using DBInterface: DBInterface

using Tables: Tables

using DuckDBUtils: Repository

using DataIngestion: is_supported, get_filter, DataIngestion

using Pipelines: get_card, to_config, Pipelines

# TODO: allow db to live in other folders
const REPOSITORY = Ref{Repository}()

# TODO: should we also write output in cache scratch space?
const OUTPUT = Ref{String}()

include("launch.jl")

function __init__()
    cache = @get_scratch!("cache")
    REPOSITORY[] = Repository(joinpath(cache, "db.duckdb"))
    OUTPUT[] = @get_scratch!("output")
end

end
