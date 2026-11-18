@kwarg struct FilesConfig
    files::Vector{String}
end

@kwarg struct TableConfig
    table::String
    schema::Maybe{String} = nothing
end

function load_files(files::FilesConfig, table::TableConfig)
    return function ()
        DataIngestion.load_files(REPOSITORY[], files.files, table.table; table.schema)
        return DataIngestion.summarize(REPOSITORY[], table.table; table.schema)
    end
end

@kwarg struct SelectionConfig
    filters::Vector{Filter}
    cols::Maybe{Vector{String}} = nothing
end

function select_data(source::TableConfig, target::TableConfig, selection::SelectionConfig)
    (; table, schema) = target
    return function ()
        DuckDBUtils.with_table_name(REPOSITORY[]; schema = target.schema) do src
            DuckDBUtils.replace_table(
                "FROM $(in_schema(source.table, source.schema));", src;
                schema, virtual = true
            )
            transform = isnothing(selection.cols) ? identity : Select(args = Get.(selection.cols))
            DataIngestion.select(
                REPOSITORY[], selection.filters, src, table; schema, transform
            )
        end
        return
    end
end

