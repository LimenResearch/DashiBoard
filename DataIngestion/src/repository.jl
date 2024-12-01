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

function with_connection(f, (; db, pool)::Repository)
    con = acquire(() -> DBInterface.connect(db), pool, isvalid = isopen)
    try
        f(con)
    finally
        release(pool, con)
    end
end

function DBInterface.execute(f::Base.Callable, repo::Repository, sql::AbstractString, params = (;))
    with_connection(repo) do conn
        DBInterface.execute(f, conn, sql, params)
    end
end

function DBInterface.execute(f::Base.Callable, repo::Repository, node::SQLNode, params = (;))
    sql = render(get_catalog(repo), node)
    return DBInterface.execute(f, repo, String(sql), pack(sql, params))
end

get_catalog(repo::Repository; kwargs...) = with_connection(con -> reflect(con; dialect = :duckdb, kwargs...), repo)
