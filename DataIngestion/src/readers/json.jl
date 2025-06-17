function json_reader(
        N::Integer;
        compression::Maybe{AbstractString} = nothing,
        filename::Bool = false,
        format::AbstractString = "auto",
        hive_partitioning::Bool = false,
        ignore_errors::Bool = false,
        maximum_sample_files::Integer = 32,
        maximum_object_size::Integer = 16777216,
        union_by_name::Bool = false,
    )

    options = StringDict(
        "compression" => compression,
        "filename" => filename,
        "format" => format,
        "hive_partitioning" => hive_partitioning,
        "ignore_errors" => ignore_errors,
        "maximum_sample_files" => maximum_sample_files,
        "maximum_object_size" => maximum_object_size,
        "union_by_name" => union_by_name,
    )

    return reader_call("read_json", N, options)
end
