"""
    to_sql(x)

Convert a julia value `x` to its SQL representation.
"""
to_sql(x) = render(LIT(x))

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

to_nrow(x)::Int64 = only(x).Count

function table_creation_summary(x, virtual::Bool = false)
    # return nothing for views, row count otherwise
    return virtual ? nothing : (; Count = to_nrow(x))
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
    return DBInterface.execute(Fix2(table_creation_summary, virtual), repository, sql, params)
end

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

    return DBInterface.execute(table_creation_summary, repository, sql, params)
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
    with_view(f, repository::Repository, table)

Register `table` under an automatically generated name `name`, apply `f(name)`,
and then unregister the table.

!!! note
    Currently passing a non-default `schema` is not supported in `with_view`.
"""
function with_view(f, repository::Repository, table)
    return with_table_name(repository, virtual = true, cleanup = false) do tmp_name
        # Temporarily register table
        register_table(repository, table, tmp_name)
        try
            f(tmp_name)
        finally
            unregister_table(repository, tmp_name)
        end
    end
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
    return with_view(repository, table) do tempname
        replace_table(repository, string("FROM \"", tempname, "\";"), name; schema)
    end
end

"""
    with_table(f, repository::Repository, table; schema::Union{AbstractString, Nothing} = nothing)

Load `table` under an automatically generated name `name`, apply `f(name)`,
and then delete the table.
"""
function with_table(f, repository::Repository, table; schema::Union{AbstractString, Nothing} = nothing)
    return with_table_name(repository; schema) do tmp_name
        load_table(repository, table, tmp_name; schema)
        f(tmp_name) # `with_table_name` cleans up automatically
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
