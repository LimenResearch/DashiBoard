module DuckDBUtils

export Batches, Repository, get_catalog, with_connections

using Base: Fix1
using FunSQL: reflect, render, pack, SQLNode
using DuckDB: DBInterface, DuckDB
using ConcurrentUtilities: Pool, acquire, release
using Tables: Tables
using OrderedCollections: OrderedDict

include("repository.jl")
include("batches.jl")

end
