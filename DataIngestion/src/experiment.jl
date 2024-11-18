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

struct Experiment
    repository::Repository
    path::String
    format::Union{Nothing, String}
    files::Union{Nothing, Vector{String}}
    directories::Directories
    metadata::Dict{String, Any}
end

function Experiment(
        path::AbstractString;
        db::Union{Nothing, DuckDB.DB} = nothing,
        pool::DuckDBPool = DuckDBPool(),
        files::Union{Nothing, AbstractVector{<:AbstractString}} = nothing,
        format::Union{Nothing, AbstractString} = nothing,
        directories::Directories = Directories(),
        metadata::AbstractDict{<:AbstractString} = Dict{String, Any}()
    )

    !isnothing(files) && isnothing(format) && (format = to_format(first(files)))

    mkpath(path)

    directories = Directories(path, directories)

    db = @something db DuckDB.DB(joinpath(path, "db.duckdb"))
    repository = Repository(db, pool)

    return Experiment(
        repository,
        path,
        format,
        files,
        directories,
        metadata
    )
end

function Experiment(path::AbstractString, files::AbstractVector{<:AbstractString}; attributes...)
    return Experiment(path; files, attributes...)
end

function initialize(ex::Experiment)
    (; files, format, repository) = ex
    isnothing(files) && throw(
        ArgumentError(
            """
            Cannot initialize experiment without files
            """
        )
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
    return ex
end

function with_experiment(f, args...; attributes...)
    exp = Experiment(args...; attributes...)
    try
        f(exp)
    finally
        DBInterface.close!(exp.repository.db)
        # TODO: additional cleanup?
    end
end
