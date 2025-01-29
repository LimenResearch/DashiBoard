module DuckDBUtils

export Batches

export Repository, acquire_connection, release_connection, with_connection, with_table

export get_catalog

export StreamResult, MaterializedResult

public colnames, to_sql

public load_table, delete_table, replace_table

public render_params

using UUIDs: uuid4
using FunSQL: reflect, render, pack, SQLNode, SQLCatalog, LIT
using DuckDB: DuckDB,
    register_table,
    unregister_table,
    StreamResult,
    MaterializedResult

using DBInterface: DBInterface
using ConcurrentUtilities: Pool, acquire, release
using Tables: Tables
using OrderedCollections: OrderedDict

include("repository.jl")
include("table.jl")
include("batches.jl")

end
