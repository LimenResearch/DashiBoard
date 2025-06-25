const DEFAULT_READERS = Dict(
    "csv" => csv_reader,
    "tsv" => csv_reader,
    "txt" => csv_reader,
    "json" => json_reader,
    "parquet" => parquet_reader,
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
    return join(items, ",\n")
end

"""
    is_supported(file::AbstractString)

Denote whether a file is of one of the available formats:
$(list_formats()).
"""
is_supported(file::AbstractString) = haskey(DEFAULT_READERS, to_format(file))

"""
    acceptable_paths()

List of relative paths corresponding to supported files within `DATA_DIR[]`.
"""
function acceptable_paths()
    base_dir = isempty(DATA_DIR[]) ? pwd() : DATA_DIR[]
    return Iterators.flatmap(walkdir(base_dir)) do (root, _, files)
        rel_root = relpath(root, base_dir)
        return (normpath(rel_root, file) for file in files if is_supported(file))
    end
end

function _joinpath(base_dir::AbstractString, path::AbstractString)
    return isempty(base_dir) ? path : joinpath(base_dir, path)
end

"""
    parse_paths(d::AbstractDict)::Vector{String}

Generate a list of file paths based on a configuration dictionary.
The file paths are interpreted as relative to `DataIngestion.DATA_DIR[]`.
"""
parse_paths(d::AbstractDict)::Vector{String} = _joinpath.(DATA_DIR[], d["files"])

# TODO: document this method and pass options via `c`
function load_files(repository::Repository, c::AbstractDict; kwargs...)
    return load_files(repository, parse_paths(c); kwargs...)
end

function load_files(repository::Repository, base_dir::AbstractString, c::AbstractDict; kwargs...)
    return @with DATA_DIR => base_dir load_files(repository, c; kwargs...)
end

"""
    load_files(
        repository::Repository,
        files::AbstractVector{<:AbstractString};
        format::AbstractString,
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
        files::AbstractVector{<:AbstractString};
        format::AbstractString = to_format(first(files)),
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

    return replace_table(repository, sql, files, TABLE_NAMES.source; schema)
end
