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
    with_connections(f, repo::Repository, n = 1)

Acquire `n` connections `(con_1, ..., con_n)` from the pool `repo.pool`.
Then, execute `f(con_1, ..., con_n)` and release the connections to the pool.
"""
function with_connections(f, (; db, pool)::Repository, n = Val{1}())
    cons = ntuple(n) do _
        acquire(() -> DBInterface.connect(db), pool, isvalid = isopen)
    end
    try
        f(cons...)
    finally
        foreach(Fix1(release, pool), cons)
    end
end

function DBInterface.execute(f::Base.Callable, repo::Repository, sql::AbstractString, params = (;))
    with_connections(repo) do conn
        DBInterface.execute(f, conn, sql, params)
    end
end

function DBInterface.execute(f::Base.Callable, repo::Repository, node::SQLNode, params = (;))
    sql = render(get_catalog(repo), node)
    return DBInterface.execute(f, repo, String(sql), pack(sql, params))
end

"""
    get_catalog(repo::Repository; schema = nothing)

Extract the catalog of available tables from a `Repository` `repo`.
"""
function get_catalog(repo::Repository; schema = nothing)
    with_connections(repo) do con
        reflect(con; dialect = :duckdb, schema)
    end
end
