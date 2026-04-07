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
function in_schema end

in_schema(name::AbstractString, ::Nothing) = string("\"", name, "\"")

function in_schema(name::AbstractString, schema::AbstractString)
    return string("\"", schema, "\".\"", name, "\"")
end

function regularize(
        repository::Repository,
        node::Union{AbstractString, SQLNode},
        params::Params = NamedTuple();
        schema::Union{AbstractString, Nothing} = nothing,
        warn::Bool = true
    )

    query, ps = if node isa AbstractString
        if warn && !isnothing(schema)
            @warn "Schema will be ignored when `query` is a SQL string"
        end
        node, params
    else
        if !isa(params, NamedParams)
            throw(ArgumentError("Named parameters are required when `node::SQLNode`"))
        end
        catalog = get_catalog(repository; schema)
        render_params(catalog, node, params)
    end
    return repository, query, ps
end

"""
    replace_table(
        repository::Repository,
        query::Union{AbstractString, SQLNode}
        [params,]
        name::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing,
        virtual::Bool = false
    )

Replace table `name` in schema `schema` in `repository.db` with the result of a given
`query` with optional parameters `params`.

Use `virtual = true` to replace a view instead of a table.

!!! note
    If `query` is an `AbstractString`, the `schema` does not apply to the `query`, only to the `name`.
    If `query` is a `SQLNode`, the `schema` appplies both to the `query` and the `name`.
"""
function replace_table(args...; schema::Union{AbstractString, Nothing} = nothing, virtual::Bool = false)
    name::AbstractString = last(args)
    repository, query, params = regularize(front(args)...; schema, warn = false)
    sql = string(
        "CREATE OR REPLACE",
        " ",
        virtual ? "VIEW" : "TABLE",
        " ",
        in_schema(name, schema),
        " AS\n",
        query
    )
    return DBInterface.execute(Returns(nothing), repository, sql, params)
end

to_nrow(x) = only(x).Count

"""
    export_table(
        repository::Repository,
        query::Union{AbstractString, SQLNode}
        [params,]
        path::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing,
        options...
    )

Export to `path` (with options `options`) the result of a given `query` with
optional parameters `params` in schema `schema` in `repository.db`.
"""
function export_table end

function export_table(args...; schema::Union{AbstractString, Nothing} = nothing, options...)
    path::AbstractString = last(args)
    repository, query, params = regularize(front(args)...; schema, warn = true)

    option_strs = [string(k, " ", v) for (k, v) in pairs(options)]

    sql = sprint() do io
        print(io, "COPY", " ", "(", query, ")", " TO ", "'", path, "'")
        if !isempty(option_strs)
            print(io, " ", "(")
            join(io, option_strs, ", ")
            print(io, ")")
        end
        print(io, ";")
    end

    return DBInterface.execute(to_nrow, repository, sql, params)
end

"""
    delete_table(
        repository::Repository,
        name::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing,
        virtual::Bool = false
    )

Delete table `name` in schema `schema` in `repository.db`.

Use `virtual = true` to delete a view instead of a table.
"""
function delete_table(
        repository::Repository,
        name::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing,
        virtual::Bool = false
    )

    sql = string(
        "DROP",
        " ",
        virtual ? "VIEW" : "TABLE",
        " IF EXISTS ",
        in_schema(name, schema)
    )
    return DBInterface.execute(Returns(nothing), repository, sql)
end

"""
    load_table(
        repository::Repository,
        table,
        name::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing
    )

Load a Julia table `table` as `name` in schema `schema` in `repository.db`.
"""
function load_table(
        repository::Repository, table, name::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing
    )
    tempname = string(uuid4())
    # Temporarily register table in order to load it
    with_connection(con -> register_table(con, table, tempname), repository)
    try
        replace_table(repository, string("FROM \"", tempname, "\";"), name; schema)
    finally
        with_connection(con -> unregister_table(con, tempname), repository)
    end
    return
end

"""
    with_table(f, repository::Repository, table; schema::Union{AbstractString, Nothing} = nothing)

Register a table under a random unique name `name`, apply `f(name)`, and then
unregister the table.
"""
function with_table(f, repository::Repository, table; schema::Union{AbstractString, Nothing} = nothing)
    name = string(uuid4())
    load_table(repository, table, name; schema)
    return try
        f(name)
    finally
        delete_table(repository, name; schema)
    end
end

"""
    colnames(repository::Repository, table::AbstractString; schema::Union{AbstractString, Nothing} = nothing)

Return list of columns for a given table.
"""
function colnames(
        repository::Repository, table::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing
    )
    catalog = get_catalog(repository; schema)
    return String[string(k) for (k, _) in catalog[table]]
end
