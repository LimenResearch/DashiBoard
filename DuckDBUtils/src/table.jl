function replace_object(object::AbstractString, repo::Repository, target::AbstractString, query; schema = nothing)
    catalog = get_catalog(repo; schema)

    sql = string(
        "CREATE OR REPLACE",
        " ",
        object,
        " ",
        in_schema(target, schema),
        " AS\n",
        render(catalog, query)
    )

    DBInterface.execute(
        Returns(nothing),
        repo,
        sql,
    )
end

function replace_table(repo::Repository, target::AbstractString, query; schema = nothing)
    replace_object("TABLE", repo, target, query; schema)
end

function replace_view(repo::Repository, target::AbstractString, query; schema = nothing)
    replace_object("TABLE", repo, target, query; schema)
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
