module DuckDBUtils

export Batches

export Repository

export acquire_connection, release_connection, drain_connections!, with_connection

export get_catalog

export StreamResult, MaterializedResult

public Appender, append, end_row, close

public colnames, to_sql, to_nrow

public load_table, delete_table, replace_table, export_table, with_table, with_view

public with_table_name, with_table_names

public render_params, in_schema, query

using Base: front, Fix1, Fix2
using FunSQL: reflect, render, pack, SQLNode, SQLCatalog, LIT
using DuckDB: DuckDB,
    query,
    register_table,
    unregister_table,
    StreamResult,
    MaterializedResult,
    Appender,
    append,
    end_row,
    close

using DBInterface: DBInterface
using ConcurrentUtilities: Pool, acquire, release, drain!, Pools
using Tables: Tables
using OrderedCollections: OrderedDict

include("repository.jl")
include("table.jl")
include("batches.jl")

end
