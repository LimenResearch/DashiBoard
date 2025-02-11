const DEFAULT_READERS = Dict(
    "csv" => csv_reader,
    "tsv" => csv_reader,
    "txt" => csv_reader,
    "json" => json_reader,
    "parquet" => parquet_reader,
)

const DEFAULT_FORMATS = Dict(
    "csv" => "CSV",
    "tsv" => "CSV",
    "txt" => "CSV",
    "json" => "JSON",
    "parquet" => "PARQUET",
)

const TABLE_NAMES = (
    source = "source",
    selection = "selection",
)

function to_format(s::AbstractString)
    _, ext = splitext(s)
    return lstrip(ext, '.')
end

function list_formats()
    items = string.("- `", keys(DEFAULT_READERS), "`")
    join(items, ",\n")
end

"""
    is_supported(file::AbstractString)

Denote whether a file is of one of the available formats:
$(list_formats()).
"""
is_supported(file::AbstractString) = haskey(DEFAULT_READERS, to_format(file))

"""
    load_files(
        repository::Repository, files::AbstractVector{<:AbstractString},
        [format::AbstractString];
        schema = nothing,
        union_by_name = true, kwargs...)
    )

Load `files` into a table called `TABLE_NAMES.source` inside `repository.db`
within the schema `schema` (defaults to main schema).

The format is inferred or can be passed explicitly.

The following formats are supported:
$(list_formats()).

`union_by_name` and the remaining keyword arguments are forwarded to the reader
for the given format.
"""
function load_files(
        repository::Repository,
        files::AbstractVector{<:AbstractString},
        format::AbstractString = to_format(first(files));
        schema = nothing,
        union_by_name = true,
        kwargs...
    )

    N = length(files)
    reader = DEFAULT_READERS[format](N; filename = true, union_by_name, kwargs...)

    sql = """
    FROM $reader
    SELECT * EXCLUDE filename, parse_filename(filename, true) AS _name
    """

    replace_table(repository, sql, files, TABLE_NAMES.source; schema)
end

function export_selection(repository::Repository, path::AbstractString; schema = nothing, format = "csv")
    source = in_schema(TABLE_NAMES.selection, schema)
    fmt = DEFAULT_FORMATS[format]

    query = """
    COPY (FROM $source) TO '$path' (FORMAT $fmt);
    """

    DBInterface.execute(Returns(nothing), repository, query)
end
