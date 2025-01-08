module DuckDBUtils

export Batches

export Repository, acquire_connection, release_connection, with_connection, with_table

export get_catalog

public colnames, to_sql

public load_table, delete_table, replace_table, replace_view

public render_params

using UUIDs: uuid4
using FunSQL: reflect, render, pack, SQLNode, SQLCatalog, LIT
using DuckDB: DBInterface, DuckDB, register_table, unregister_table
using ConcurrentUtilities: Pool, acquire, release
using Tables: Tables
using OrderedCollections: OrderedDict

include("repository.jl")
include("table.jl")
include("batches.jl")

end
