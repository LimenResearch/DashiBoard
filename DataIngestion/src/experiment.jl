@kwdef struct Directories
    configs::String = "configs"
    outputs::String = "outputs"
    figures::String = "figures"
end

function Directories(path::AbstractString, d::Directories)
    configs = mkpath(joinpath(path, d.configs))
    outputs = mkpath(joinpath(path, d.outputs))
    figures = mkpath(joinpath(path, d.figures))
    return Directories(configs, outputs, figures)
end

function print_list(io, files::Vector{String}, delim = true)
    delim && print(io, "[")
    for (isfirst, file) in flagfirst(files)
        isfirst || print(io, ", ")
        print(io, "'")
        print(io, file)
        print(io, "'")
    end
    delim && print(io, "]")
end

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
    partition = "partition",
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

mutable struct Experiment
    const repository::Repository
    const prefix::String
    const name::String
    const format::String
    const files::Vector{String}
    const directories::Directories
    const metadata::Dict{String, Any}
    names::Vector{String}
end

function Experiment(;
        db::Union{Nothing, DuckDB.DB} = nothing,
        pool::DuckDBPool = DuckDBPool(),
        prefix::AbstractString,
        name::AbstractString,
        files::AbstractVector{<:AbstractString},
        format::AbstractString = to_format(first(files)),
        directories::Directories = Directories(),
        metadata::AbstractDict{<:AbstractString} = Dict{String, Any}()
    )

    path = mkpath(joinpath(prefix, name))

    directories = Directories(path, directories)

    db = @something db DuckDB.DB(joinpath(path, "$name.duckdb"))
    repository = Repository(db, pool)

    return Experiment(
        repository,
        prefix,
        name,
        format,
        files,
        directories,
        metadata,
        String[]
    )
end

function init!(ex::Experiment; load)
    load && load_source(ex)
    register_subtable_names!(ex)
    return ex
end

function load_source(ex::Experiment)
    (; files, format, repository) = ex
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

function register_subtable_names!(ex::Experiment)
    query = From(TABLE_NAMES.source) |> Group(Get._name) |> Select(Get._name)
    ex.names = DBInterface.execute(ex.repository, query) do res
        return String[row._name for row in res]
    end
end
