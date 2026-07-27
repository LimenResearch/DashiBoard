function parquet_reader(
        N::Integer;
        binary_as_string::Bool = false,
        encryption_config::Maybe{StringStruct} = nothing,
        file_row_number::Bool = false,
        hive_partitioning::Bool = true,
        union_by_name::Bool = false
    )

    options = StringDict(
        "binary_as_string" => binary_as_string,
        "encryption_config" => encryption_config,
        "file_row_number" => file_row_number,
        "hive_partitioning" => hive_partitioning,
        "union_by_name" => union_by_name,
    )

    return reader_call("read_parquet", N, options)
end
