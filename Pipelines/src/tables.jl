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
        id_var::AbstractPrimaryKey, sel::AbstractVector;
        schema::Union{AbstractString, Nothing} = nothing
    )

    isempty(sel) && return

    original, extra = in_schema(orig, schema), in_schema(t, schema)

    specs = get_colspecs(repository, t; schema)
    alter = [
        "ALTER TABLE $(original) ADD COLUMN IF NOT EXISTS $(specs[k]);"
            for k in sel
    ]

    cols = string.("\"", sel, "\"")
    ALTERATIONS = join(alter, "\n")
    COLUMNS = join(cols, ", ")
    UPDATES = join(string.(cols, " = ", extra, ".", cols), ", ")

    DuckDBUtils.transaction(
        repository,
        """
        $(ALTERATIONS)
        UPDATE $(original)
            SET $(UPDATES)
            FROM $(extra)
            WHERE $(extra).\"$(id_var)\" = $(original).\"$(id_var)\";
        """
    )

    return
end
