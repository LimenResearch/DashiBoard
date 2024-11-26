module DashiBoard

public launch

using HTTP: HTTP
using Oxygen: json, @post, serve
using Scratch: @get_scratch!

using JSON3: JSON3

using JSONTables: arraytable

using DuckDB, Dates, Tables

using DataIngestion, Pipelines

const REPOSITORY = Ref{Repository}()

include("serve.jl")

function __init__()
    cache = @get_scratch!("cache")
    REPOSITORY[] = Repository(joinpath(cache, "db.duckdb"))
end

end
