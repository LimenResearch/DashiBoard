module DashiBoard

public launch

using HTTP: HTTP
using Oxygen: json, @post, serve
using Scratch: @get_scratch!

using JSON3: JSON3

using JSONTables: arraytable

using DuckDB: DBInterface, DuckDB

using Tables: Tables

using DataIngestion: is_supported, Filters, Repository, DataIngestion

using Pipelines: Cards, Pipelines

const REPOSITORY = Ref{Repository}()

include("launch.jl")

function __init__()
    cache = @get_scratch!("cache")
    REPOSITORY[] = Repository(joinpath(cache, "db.duckdb"))
end

end
