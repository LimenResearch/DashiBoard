function parquet_reader(
        N::Integer;
        binary_as_string::Bool = false,
        encryption_config::Maybe{StringStruct} = nothing,
        filename::Bool = false,
        file_row_number::Bool = false,
        hive_partitioning::Bool = true,
        union_by_name::Bool = false
    )

    options = StringDict(
        "binary_as_string" => binary_as_string,
        "encryption_config" => encryption_config,
        "filename" => filename,
        "file_row_number" => file_row_number,
        "hive_partitioning" => hive_partitioning,
        "union_by_name" => union_by_name,
    )

    return reader_call("read_parquet", N, options)
end
