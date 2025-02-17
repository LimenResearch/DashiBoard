const UnnamedParams = Union{Tuple, AbstractVector}
const NamedParams = Union{NamedTuple, AbstractDict}
const Params = Union{NamedParams, UnnamedParams}

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

"""
    replace_table(
        repository::Repository,
        query::Union{AbstractString, SQLNode}
        [params,]
        name::AbstractString;
        schema = nothing,
        virtual::Bool = false
    )

Replace table `name` in schema `schema` in `repository.db` with the result of a given
`query` with optional parameters `params`.

Use `virtual = true` to replace a view instead of a table.
"""
function replace_table end

function replace_table(
        repository::Repository,
        query::AbstractString,
        params::Params,
        name::AbstractString;
        schema = nothing,
        virtual::Bool = false
    )

    sql = string(
        "CREATE OR REPLACE",
        " ",
        virtual ? "VIEW" : "TABLE",
        " ",
        in_schema(name, schema),
        " AS\n",
        query
    )

    DBInterface.execute(Returns(nothing), repository, sql, params)
end

function replace_table(
        repository::Repository,
        node::SQLNode,
        params::NamedParams,
        name::AbstractString;
        schema = nothing,
        virtual::Bool = false
    )

    catalog = get_catalog(repository; schema)
    query, ps = render_params(catalog, node, params)
    replace_table(repository, query, ps, name; schema, virtual)
end

function replace_table(
        repository::Repository,
        query::Union{SQLNode, AbstractString},
        name::AbstractString;
        schema = nothing,
        virtual::Bool = false
    )

    params = NamedTuple()
    replace_table(repository, query, params, name; schema, virtual)
end

"""
    delete_table(
        repository::Repository,
        name::AbstractString;
        schema = nothing,
        virtual::Bool = false
    )

Delete table `name` in schema `schema` in `repository.db`.

Use `virtual = true` to delete a view instead of a table.
"""
function delete_table(
        repository::Repository,
        name::AbstractString;
        schema = nothing,
        virtual::Bool = false
    )

    sql = string(
        "DROP",
        " ",
        virtual ? "VIEW" : "TABLE",
        " ",
        in_schema(name, schema)
    )
    DBInterface.execute(Returns(nothing), repository, sql)
end

"""
    load_table(
        repository::Repository,
        table,
        name::AbstractString;
        schema = nothing
    )

Load a Julia table `table` as `name` in schema `schema` in `repository.db`.
"""
function load_table(repository::Repository, table, name::AbstractString; schema = nothing)
    tempname = string(uuid4())
    # Temporarily register table in order to load it
    with_connection(con -> register_table(con, table, tempname), repository)
    replace_table(repository, string("FROM \"", tempname, "\";"), name; schema)
    with_connection(con -> unregister_table(con, tempname), repository)
end

"""
    with_table(f, repository::Repository, table; schema = nothing)

Register a table under a random unique name `name`, apply `f(name)`, and then
unregister the table.
"""
function with_table(f, repository::Repository, table; schema = nothing)
    name = string(uuid4())
    load_table(repository, table, name; schema)
    try
        f(name)
    finally
        delete_table(repository, name; schema)
    end
end

"""
    colnames(repository::Repository, table::AbstractString; schema = nothing)

Return list of columns for a given table.
"""
function colnames(repository::Repository, table::AbstractString; schema = nothing)
    catalog = get_catalog(repository; schema)
    return [string(k) for (k, _) in catalog[table]]
end
