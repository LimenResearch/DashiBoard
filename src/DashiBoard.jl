module DashiBoard

public launch

using HTTP: HTTP
using Oxygen: json, @post, serve
using Scratch: @get_scratch!

using JSON3: JSON3

using JSONTables: arraytable

using DBInterface: DBInterface

using Tables: Tables

using DuckDBUtils: Repository

using DataIngestion: is_supported, Filters, DataIngestion

using Pipelines: Cards, Pipelines

# TODO: allow db to live in other folders
const REPOSITORY = Ref{Repository}()

include("launch.jl")

function __init__()
    cache = @get_scratch!("cache")
    REPOSITORY[] = Repository(joinpath(cache, "db.duckdb"))
end

end
