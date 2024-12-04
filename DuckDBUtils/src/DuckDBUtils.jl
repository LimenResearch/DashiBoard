module DuckDBUtils

export Batches, Repository, get_catalog, with_connection

using FunSQL: reflect, render, pack, SQLNode
using DuckDB: DBInterface, DuckDB
using ConcurrentUtilities: Pool, acquire, release
using Tables: Tables
using OrderedCollections: OrderedDict

include("repository.jl")
include("batches.jl")

end
