const UnnamedParams = Union{Tuple, AbstractVector}
const NamedParams = Union{NamedTuple, AbstractDict}
const Params = Union{NamedParams, UnnamedParams}

const DEFAULT_SCHEMA = "main"

struct MultiDict
    dict::Dict{String, Set{Int}}
    lock::ReentrantLock
    limit::Int
end

MultiDict(limit::Integer = 4096) = MultiDict(Dict{String, Set{Int}}(), ReentrantLock(), Int(limit))

# Find first `n` positive integers not in `s`.
# Append them to `s` and return them.
# Throw if this would cause `length(s)` to exceed `limit`
function first_not_in!(s::AbstractSet{<:Integer}, n::Integer; limit::Integer = 4096)
    L = n + length(s)
    L > limit && throw(ArgumentError("Too many values were requested"))
    idxs::Vector{Int} = first(setdiff(1:L, s), n)
    union!(s, idxs)
    return idxs
end

function acquire_numbers(d::MultiDict, k::AbstractString, n::Integer = 1)
    return @lock d.lock begin
        taken = get!(() -> Set{Int}(), d.dict, k)
        first_not_in!(taken, n)
    end
end

function release_numbers(d::MultiDict, k::AbstractString, is::AbstractVector)
    @lock d.lock begin
        taken = d.dict[k]
        setdiff!(taken, is)
    end
    return
end

struct Connections
    pool::Pool{Nothing, DuckDB.Connection}
    Connections(limit::Integer = 4096) = new(Pool{Nothing, DuckDB.Connection}(Int(limit)))
end

function Base.show(io::IO, connections::Connections)
    print(io, "Connections(limit = ", Pools.limit(connections.pool), ")")
    return
end

function acquire_connection(connections::Connections, db::DuckDB.DB)
    return acquire(() -> DBInterface.connect(db), connections.pool, isvalid = isopen)
end

function release_connection(connections::Connections, con::DuckDB.Connection)
    return release(connections.pool, con)
end

drain_connections!(connections::Connections) = drain!(connections.pool)

struct Repository
    db::DuckDB.DB
    connections::Connections
    private_tables::MultiDict
    private_views::MultiDict
end

"""
    Repository(db::DuckDB.DB = DuckDB.DB(); limit::Integer = 4096, table_limit::Integer = 4096, view_limit::Integer = 4096)

Construct a `Repository` object that holds a `DuckDB.DB` as well as a pool of
connections.

The keyword argument `limit` denotes the maximum number of simultaneous connections to the database.

A repository reserves tables of the form `_table_{number}` (with number in `1..table_limit`)
and views of the form `_view_{number}` (with number in `1..view_limit`) as temporary helpers for computations.

Use `DBInterface.execute(f::Base.Callable, repository::Repository, sql::AbstractString, [params])`
to run a function on the result of a query `sql` on an available connection in the pool.
"""
function Repository(db::DuckDB.DB = DuckDB.DB(); limit::Integer = 4096, table_limit::Integer = 4096, view_limit::Integer = 4096)
    return Repository(db, Connections(limit), MultiDict(table_limit), MultiDict(view_limit))
end

function Repository(path::AbstractString; limit::Integer = 4096, table_limit::Integer = 4096, view_limit::Integer = 4096)
    return Repository(DuckDB.DB(path); limit, table_limit, view_limit)
end

function Base.show(io::IO, repository::Repository)
    print(io, "Repository(")
    show(io, repository.db)
    print(io, ", ")
    show(io, repository.connections)
    print(io, ")")
    return
end

"""
    acquire_connection(repository::Repository)

Acquire an open connection to the database `repository.db` from the pool `repository.pool`.
See also [`release_connection`](@ref).

!!! note
    A command `con = acquire_connection(repository)` must always be followed by a matching
    command `release_connection(repository, con)` (after the connection has been used).
"""
function acquire_connection(repository::Repository)
    (; db, connections) = repository
    return acquire_connection(connections, db)
end

"""
    release_connection(repository::Repository, con)

Release connection `con` to the pool `repository.connections`.
"""
release_connection(repository::Repository, con) = release_connection(repository.connections, con)

"""
    drain_connections!(repository::Repository)

Make existing connections from the pool `repository.connections` no longer reusable.
"""
drain_connections!(repository::Repository) = drain_connections!(repository.connections)

"""
    with_connection(f, repository::Repository, [N])

Acquire a connection `con` from the pool `repository.pool`.
Then, execute `f(con)` and release the connection to the pool.
An optional parameter `N` can be passed to determine the number of
connections to be acquired (defaults to `1`).
"""
function with_connection(f, repository::Repository, N = Val{1}())
    cons = ntuple(_ -> acquire_connection(repository), N)
    return try
        f(cons...)
    finally
        foreach(con -> release_connection(repository, con), cons)
    end
end

"""
    get_catalog(repository::Repository; schema::Union{AbstractString, Nothing} = nothing)

Extract the catalog of available tables from a `Repository` `repository`.
"""
function get_catalog(repository::Repository; schema::Union{AbstractString, Nothing} = nothing)
    return with_connection(repository) do con
        reflect(con; dialect = :duckdb, schema)
    end
end

function DBInterface.execute(
        f::Base.Callable, repository::Repository,
        sql::AbstractString, params = NamedTuple()
    )
    return with_connection(repository) do con
        DBInterface.execute(f, con, sql, params)
    end
end

"""
    render_params(catalog::SQLCatalog, node::SQLNode, params::Union{NamedTuple, AbstractDict} = NamedTuple())

Return query string and parameter list from query expressed as `node`.
"""
function render_params(catalog::SQLCatalog, node::SQLNode, params::NamedParams = NamedTuple())
    sql = render(catalog, node)
    return String(sql), pack(sql, params)
end

function DBInterface.execute(
        f::Base.Callable,
        repository::Repository,
        node::SQLNode,
        params = NamedTuple();
        schema::Union{AbstractString, Nothing} = nothing
    )
    catalog = get_catalog(repository; schema)
    q, ps = render_params(catalog, node, params)
    return DBInterface.execute(f, repository, q, ps)
end

function DuckDB.query(f, r::Repository, sql::AbstractString)
    return with_connection(r) do con
        res = query(con, sql)
        try
            f(res)
        finally
            DBInterface.close!(res)
        end
    end
end

function transaction(r::Repository, sql::AbstractString)
    t = string("BEGIN TRANSACTION;\n", sql, "\nCOMMIT;")
    try
        query(Returns(nothing), r, t)
    catch
        query(Returns(nothing), r, "ROLLBACK;")
        rethrow()
    end
    return
end

function DuckDB.register_table(r::Repository, tbl, name::AbstractString)
    return with_connection(con -> register_table(con, tbl, name), r)
end

function DuckDB.unregister_table(r::Repository, name::AbstractString)
    return with_connection(con -> unregister_table(con, name), r)
end

"""
    with_table_names(
        f, r::Repository, n::Integer;
        schema::Union{AbstractString, Nothing} = nothing,
        virtual::Bool = false,
        cleanup::Bool = true
    )

Reserve `n` table names within `schema`, call `f` using as argument the list of names,
then unreserve the table names.

Use `virtual = true` to reserve names for SQL views rather than tables.

The tables are automatically deleted if `cleanup = true` (default).

See also [`with_table_name`](@ref).
"""
function with_table_names(
        f, r::Repository, n::Integer;
        schema::Union{AbstractString, Nothing} = nothing,
        virtual::Bool = false,
        cleanup::Bool = true
    )
    prefix = virtual ? "view" : "table"
    d = virtual ? r.private_views : r.private_tables
    key = something(schema, DEFAULT_SCHEMA)
    is = acquire_numbers(d, key, n)
    names = string.("_", prefix, "_", is)
    return try
        f(names)
    finally
        release_numbers(d, key, is)
        cleanup && foreach(name -> delete_table(r, name; virtual), names)
    end
end

"""
    with_table_name(
        f, r::Repository;
        schema::Union{AbstractString, Nothing} = nothing,
        virtual::Bool = false,
        cleanup::Bool = true
    )

Reserve a table name within `schema`, call `f` using as that name as argument,
then unreserve the table name.

Use `virtual = true` to reserve a name for a SQL view rather than a table.

The tables are automatically deleted if `cleanup = true` (default).

See also [`with_table_names`](@ref).
"""
function with_table_name(
        f, r::Repository;
        schema::Union{AbstractString, Nothing} = nothing,
        virtual::Bool = false,
        cleanup::Bool = true
    )
    return with_table_names(f ∘ only, r, 1; schema, virtual, cleanup)
end
