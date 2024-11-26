module DashiBoard

using HTTP: HTTP
using Oxygen: json, @post, serve
using Scratch: @get_scratch!

using JSON3, JSONTables, DuckDB, Dates, Tables

using DataIngestion, Pipelines

include("serve.jl")

end