const VALID_FORMATS = [
    "csv" => "read_csv",
    "tsv" => "read_csv",
    "txt" => "read_csv",
    "json" => "read_json",
    "parquet" => "read_parquet",
]

const DEFAULT_READERS = Dict{String, String}(VALID_FORMATS)

function print_supported_formats(io::IO)
    fmts = @. string("- `", first(VALID_FORMATS), "`")
    join(io, fmts, ",\n")
end

sprint_supported_formats() = sprint(print_supported_formats)

const TABLE_NAMES = (
    source = "source",
    selection = "selection",
)

function to_format(s::AbstractString)
    _, ext = splitext(s)
    return lstrip(ext, '.')
end

"""
    is_supported(file::AbstractString)

Denote whether a file is of one of the available formats:
$(sprint_supported_formats()).
"""
is_supported(file::AbstractString) = haskey(DEFAULT_READERS, to_format(file))

"""
    load_files(
        repository::Repository, files::AbstractVector{<:AbstractString},
        [format::AbstractString]
    )

Load `files` into a table called `TABLE_NAMES.source` inside `repository.db`.
The format is inferred or can be passed explicitly.

The following formats are supported:
$(sprint_supported_formats()).
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
