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

function load_table(con::DuckDB.Connection, table, name::AbstractString, schema = nothing)
    schema = something(schema, "main")
    tempname = string(uuid4())
    # Temporarily register table in order to load it
    register_table(con, table, tempname)
    DBInterface.execute(
        Returns(nothing), con, """
        CREATE OR REPLACE TABLE "$(schema)"."$(name)" AS FROM "$(tempname)";
        """
    )
    unregister_table(con, tempname)
end

function load_table(repo::Repository, table, name::AbstractString, schema = nothing)
    with_connection(con -> load_table(con, table, name, schema), repo)
end

function delete_table(con::DuckDB.Connection, name::AbstractString, schema = nothing)
    schema = something(schema, "main")
    DBInterface.execute(
        Returns(nothing), con, """
        DROP TABLE "$(schema)"."$(name)";
        """
    )
end

function delete_table(repo::Repository, name::AbstractString, schema = nothing)
    with_connection(con -> delete_table(con, name, schema), repo)
end

"""
    with_table(f, repo::Repository, table; schema = nothing)

Register a table under a random unique name `name`, apply `f(name)`, and then
unregister the table.
"""
function with_table(f, repo::Repository, table; schema = nothing)
    name = string(uuid4())
    load_table(repo, table, name, schema)
    try
        f(name)
    finally
        delete_table(repo, name, schema)
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

function DBInterface.execute(f::Base.Callable, repo::Repository, node::SQLNode, params = (;); schema = nothing)
    sql = render(get_catalog(repo; schema), node)
    return DBInterface.execute(f, repo, String(sql), pack(sql, params))
end
