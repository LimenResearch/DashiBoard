module DuckDBUtils

export Batches

export Repository, acquire_connection, release_connection, with_connection, with_table

export get_catalog

public in_schema, replace_table, replace_view

using UUIDs: uuid4
using FunSQL: reflect, render, pack, SQLNode
using DuckDB: DBInterface, DuckDB, register_table, unregister_table
using ConcurrentUtilities: Pool, acquire, release
using Tables: Tables
using OrderedCollections: OrderedDict

include("repository.jl")
include("table.jl")
include("batches.jl")

end
