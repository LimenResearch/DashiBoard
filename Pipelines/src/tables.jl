# This simple table type is the preferred way to store tables in memory
const SimpleTable = OrderedDict{String, AbstractVector}

function fromtable(data)
    cols = Tables.columns(data)
    tbl = SimpleTable()
    for k in Tables.columnnames(cols)
        tbl[string(k)] = Tables.getcolumn(cols, k)
    end
    return tbl
end

join_names(args...) = join(args, "_")

function get_colspecs(
        repository::Repository, t::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing
    )

    return DBInterface.execute(repository, "DESCRIBE $(in_schema(t, schema));") do res
        d = Dict{String, String}()
        for row in Tables.rows(res)
            (; column_name, column_type) = row
            d[column_name] = string("\"", column_name, "\" ", column_type)
        end
        return d
    end
end

function join_on_id_var(
        repository::Repository,
        orig::AbstractString, t::AbstractString,
        id_var::AbstractString, sel::AbstractVector;
        schema::Union{AbstractString, Nothing} = nothing
    )

    isempty(sel) && return

    specs = get_colspecs(repository, t; schema)
    alter = [
        "ALTER TABLE $(in_schema(orig, schema)) ADD COLUMN IF NOT EXISTS $(specs[k]);"
            for k in sel
    ]

    with_table_names(repository, 2, cleanup = false) do (original, extra)
        ALTERATIONS = join(alter, "\n")
        COLUMNS = join(string.("\"", sel, "\""), ", ")
        UPDATES = join(string.("\"", sel, "\"", " = ", "\"", extra, "\".\"", sel, "\""), ", ")
        DuckDBUtils.query(
            Returns(nothing),
            repository,
            """
            BEGIN TRANSACTION;
            $(ALTERATIONS);
            UPDATE $(in_schema(orig, schema)) AS "$(original)"
                SET $(UPDATES)
                FROM $(in_schema(t, schema)) AS "$(extra)"
                WHERE "$(extra)"."$(id_var)" = "$(original)"."$(id_var)";
            COMMIT;
            """
        )
    end
    return
end
