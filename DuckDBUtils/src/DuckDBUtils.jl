module DuckDBUtils

export Batches

export Repository

export acquire_connection, release_connection, drain_connections!

export with_connection, with_appender

export get_catalog

export StreamResult, MaterializedResult

public Appender, append, end_row, close

public colnames, to_sql, to_nrow

public initialize_table, load_table, delete_table, replace_table, export_table

public with_table, with_view, with_table_name, with_table_names

public SQLMacro, execute_with_macros

public render_params, in_schema, query, transaction

public get_scratch_space, get_scratch_file

using Base: front, Fix1, Fix2
using Scratch: @get_scratch!

using FunSQL: reflect, render, pack, SQLNode, SQLCatalog, SQLDialect, LIT
using DuckDB: DuckDB,
    query,
    register_table,
    unregister_table,
    StreamResult,
    MaterializedResult,
    Appender,
    append,
    end_row

using DBInterface: DBInterface
using ConcurrentUtilities: Pool, acquire, release, drain!, Pools
using Tables: Tables
using OrderedCollections: OrderedDict

# we use `OncePerProcess` to set a "global const" exactly once
const scratch_space = Base.OncePerProcess{String}(() -> @get_scratch!("tables"))

get_scratch_space() = scratch_space()

function get_scratch_file(file::AbstractString)
    path = abspath(joinpath(get_scratch_space(), file))
    if !startswith(path, get_scratch_space())
        throw(ArgumentError("Invalid file $(file), please pass a valid filename."))
    end
    if isdir(path)
        throw(ArgumentError("$(path) is already a directory."))
    end
    return path
end

include("repository.jl")
include("table.jl")
include("macro.jl")
include("batches.jl")

end
