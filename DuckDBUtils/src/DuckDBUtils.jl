module DuckDBUtils

export Repository, get_catalog, with_connection

using FunSQL: reflect, render, pack, SQLNode
using DuckDB: DBInterface, DuckDB
using ConcurrentUtilities: Pool, acquire, release

include("repository.jl")

end
