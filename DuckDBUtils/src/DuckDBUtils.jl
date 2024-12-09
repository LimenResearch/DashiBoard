module DuckDBUtils

export Batches

export Repository, with_connection, acquire_connection, release_connection

export get_catalog

export register_table, unregister_table

using FunSQL: reflect, render, pack, SQLNode
using DuckDB: DBInterface, DuckDB, register_table, unregister_table
using ConcurrentUtilities: Pool, acquire, release
using Tables: Tables
using OrderedCollections: OrderedDict

include("repository.jl")
include("batches.jl")

end
