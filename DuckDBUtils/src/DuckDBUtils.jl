module DuckDBUtils

export Batches

export Repository, with_connection, acquire_connection, release_connection

export get_catalog

using Base: Fix1
using FunSQL: reflect, render, pack, SQLNode
using DuckDB: DBInterface, DuckDB
using ConcurrentUtilities: Pool, acquire, release
using Tables: Tables
using OrderedCollections: OrderedDict

include("repository.jl")
include("batches.jl")

end
