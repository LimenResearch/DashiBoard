const DuckDBPool = Pool{Nothing, DuckDB.Connection}

struct Repository
    db::DuckDB.DB
    pool::DuckDBPool
end

"""
    Repository(db::DuckDB.DB)

Construct a `Repository` object that holds a `DuckDB.DB` as well as a pool of
connections.

Use `DBInterface.(f::Base.Callable, repo::Repository, sql::AbstractString, [params])`
to run a function on the result of a query `sql` on an available connection in the pool.
"""
Repository(db::DuckDB.DB) = Repository(db, DuckDBPool())

Repository(path::AbstractString) = Repository(DuckDB.DB(path))

Repository() = Repository(DuckDB.DB())

"""
    acquire_connection(repo::Repository)

Acquire an open connection to the database `repo.db` from the pool `repo.pool`.
See also [`release_connection`](@ref).

!!! note
    A command `con = acquire_connection(repo)` must always be followed by a matching
    command `release_connection(repo, con)` (after the connection has been used).
"""
function acquire_connection(repo::Repository)
    (; db, pool) = repo
    return acquire(() -> DBInterface.connect(db), pool, isvalid = isopen)
end

"""
    release_connection(repo::Repository, con)

Release connection `con` to the pool `repo.pool`
"""
release_connection(repo::Repository, con) = release(repo.pool, con)

"""
    with_connection(f, repo::Repository, [N])

Acquire a connection `con` from the pool `repo.pool`.
Then, execute `f(con)` and release the connection to the pool.
An optional parameter `N` can be passed to determine the number of
connections to be acquired (defaults to `1`).
"""
function with_connection(f, repo::Repository, N = Val{1}())
    cons = ntuple(_ -> acquire_connection(repo), N)
    try
        f(cons...)
    finally
        foreach(con -> release_connection(repo, con), cons)
    end
end

"""
    get_catalog(repo::Repository; schema = nothing)

Extract the catalog of available tables from a `Repository` `repo`.
"""
function get_catalog(repo::Repository; schema = nothing)
    with_connection(repo) do con
        reflect(con; dialect = :duckdb, schema)
    end
end

function DBInterface.execute(f::Base.Callable, repo::Repository, sql::AbstractString, params = (;))
    with_connection(repo) do con
        DBInterface.execute(f, con, sql, params)
    end
end

"""
    render_params(catalog::SQLCatalog, node::SQLNode, params = (;))

Return query string and parameter list from query expressed as `node`.
"""
function render_params(catalog::SQLCatalog, node::SQLNode, params = (;))
    sql = render(catalog, node)
    return String(sql), pack(sql, params)
end

function DBInterface.execute(f::Base.Callable, repo::Repository, node::SQLNode, params = (;); schema = nothing)
    catalog = get_catalog(repo; schema)
    q, ps = render_params(catalog, node, params)
    return DBInterface.execute(f, repo, q, ps)
end

"""
    to_sql(x)

Convert a julia value `x` to its SQL representation.
"""
to_sql(x) = render(LIT(x))
