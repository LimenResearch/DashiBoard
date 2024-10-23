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
    const reader::String
    const source::String
    const directories::Directories
    const file::String
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

    reader = DEFAULT_READERS[format]

    path = mkpath(joinpath(prefix, name))

    directories = Directories(path, directories)

    file = joinpath(path, "$name.parquet")

    source = sprint(print_list, files)

    db = @something db DuckDB.DB(joinpath(path, "$name.duckdb"))
    repository = Repository(db, pool)

    return Experiment(
        repository,
        prefix,
        name,
        format,
        reader,
        source,
        directories,
        file,
        metadata,
        String[]
    )
end

function init!(ex::Experiment)
    isfile(ex.file) || write_parquet(ex)

    define_source_table(ex)
    register_subtable_names!(ex)

    return ex
end

function write_parquet(ex::Experiment)
    query = """
    COPY (
        FROM $(ex.reader)($(ex.source), union_by_name = true, filename = true)
        SELECT * EXCLUDE filename, parse_filename(filename, true) AS _name
    )
    TO '$(ex.file)'
    (FORMAT 'parquet');
    """
    DBInterface.execute(Returns(nothing), ex.repository, query)
end

function define_source_table(ex::Experiment)
    query = """
    CREATE OR REPLACE VIEW $(ex.name) AS (
        FROM read_parquet('$(ex.file)')
    );
    """
    DBInterface.execute(Returns(nothing), ex.repository, query)
end

function register_subtable_names!(ex::Experiment)
    query = """
    SELECT _name
    FROM $(ex.name)
    GROUP BY _name;
    """
    ex.names = DBInterface.execute(ex.repository, query) do res
        return String[row._name for row in res]
    end
end
