const DEFAULT_READERS = Dict{String, String}(
    "csv" => "read_csv",
    "tsv" => "read_csv",
    "txt" => "read_csv",
    "json" => "read_json",
    "parquet" => "read_parquet",
)

const TABLE_NAMES = (
    source = "source",
    selection = "selection",
)

function to_format(s::AbstractString)
    _, ext = splitext(s)
    fmt = lstrip(ext, '.')
    if haskey(DEFAULT_READERS, fmt)
        return fmt
    else
        valid_formats = collect(keys(DEFAULT_READERS))
        sort!(valid_formats)
        error(
            """
            Automated format detection failed. Detected invalid format '$fmt'.
            Valid formats are $(sprint(print_list, valid_formats, false)).
            """
        )
    end
end

"""
    load_files(
        repository::Repository, files::AbstractVector{<:AbstractString},
        [format::AbstractString]
    )

Load `files` into a table called `TABLE_NAMES.source` inside `repository.db`.
The format is inferred or can be passed explicitly.

Supported formats are
- `"csv"`,
- `"tsv"`,
- `"txt"`,
- `"json"`,
- `"parquet"`.
"""
function load_files(
        repository::Repository, files::AbstractVector{<:AbstractString},
        format::AbstractString = to_format(first(files))
    )

    N = length(files)
    placeholders = join(string.('$', 1:N), ", ")
    reader = DEFAULT_READERS[format]
    sql = """
    CREATE OR REPLACE TABLE $(TABLE_NAMES.source) AS
    FROM $reader([$placeholders], union_by_name = true, filename = true)
    SELECT * EXCLUDE filename, parse_filename(filename, true) AS _name
    """
    DBInterface.execute(Returns(nothing), repository, sql, files)
end
