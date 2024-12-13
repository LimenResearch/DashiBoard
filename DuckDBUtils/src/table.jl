in_schema(name::AbstractString, ::Nothing) = string("\"", name, "\"")

"""
    in_schema(name::AbstractString, schema::Union{AbstractString, Nothing})

Utility to create a name to refer to a table within the schema.

For instance

```julia-repl
julia> print(in_schema("tbl", nothing))
"tbl"
julia> print(in_schema("tbl", "schm"))
"schm"."tbl"
```
"""
function in_schema(name::AbstractString, schema::AbstractString)
    return string("\"", schema, "\".\"", name, "\"")
end

function replace_object(
        object::AbstractString,
        repo::Repository,
        query::AbstractString,
        target::AbstractString;
        schema = nothing
    )

    sql = string(
        "CREATE OR REPLACE",
        " ",
        object,
        " ",
        in_schema(target, schema),
        " AS\n",
        query
    )

    DBInterface.execute(
        Returns(nothing),
        repo,
        sql,
    )
end

function replace_object(
        object::AbstractString,
        repo::Repository,
        node::SQLNode,
        target::AbstractString;
        schema = nothing
    )

    catalog = get_catalog(repo; schema)
    query = render(catalog, node)
    replace_object(object, repo, query, target; schema)
end

function replace_table(repo::Repository, query, target::AbstractString; schema = nothing)
    replace_object("TABLE", repo, query, target; schema)
end

function replace_view(repo::Repository, query, target::AbstractString; schema = nothing)
    replace_object("TABLE", repo, query, target; schema)
end

function delete_table(repo::Repository, name::AbstractString; schema = nothing)
    DBInterface.execute(Returns(nothing), repo, "DROP TABLE $(in_schema(name, schema));")
end

function load_table(repo::Repository, table, name::AbstractString; schema = nothing)
    tempname = string(uuid4())
    # Temporarily register table in order to load it
    with_connection(con -> register_table(con, table, tempname), repo)
    replace_table(repo, string("From \"", tempname, "\";"), name; schema)
    with_connection(con -> unregister_table(con, tempname), repo)
end

"""
    with_table(f, repo::Repository, table; schema = nothing)

Register a table under a random unique name `name`, apply `f(name)`, and then
unregister the table.
"""
function with_table(f, repo::Repository, table; schema = nothing)
    name = string(uuid4())
    load_table(repo, table, name; schema)
    try
        f(name)
    finally
        delete_table(repo, name; schema)
    end
end


"""
    colnames(repo::Repository, table::AbstractString; schema = nothing)

Return list of columns for a given table.
"""
function colnames(repo::Repository, table::AbstractString; schema = nothing)
    catalog = get_catalog(repo; schema)
    return [string(k) for (k, _) in catalog[table]]
end
