const DEFAULT_READERS = OrderedDict{String, String}(
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
        repository::Repository, files::AbstractVector{<:AbstractString},
        format::AbstractString = to_format(first(files));
        schema = nothing,
        union_by_name = true, kwargs...
    )

    N = length(files)
    placeholders = join(string.('$', 1:N), ", ")
    reader = DEFAULT_READERS[format]

    options = [:filename => true, :union_by_name => union_by_name, pairs(kwargs)...]
    options_str = join([string(k, " =  ", to_sql(v)) for (k, v) in options], ", ")

    sql = """
    FROM $reader([$placeholders], $options_str)
    SELECT * EXCLUDE filename, parse_filename(filename, true) AS _name
    """

    replace_table(repository, sql, TABLE_NAMES.source, files; schema)
end
