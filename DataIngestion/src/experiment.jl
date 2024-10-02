@kwdef struct Directories
    source::String = "source"
    configs::String = "configs"
    outputs::String = "outputs"
    figures::String = "figures"
end

function Directories(path::AbstractString, d::Directories)
    source = mkpath(joinpath(path, d.source))
    configs = mkpath(joinpath(path, d.configs))
    outputs = mkpath(joinpath(path, d.outputs))
    figures = mkpath(joinpath(path, d.figures))
    return Directories(source, configs, outputs, figures)
end

mutable struct Experiment
    const repository::Repository
    const prefix::String
    const name::String
    const ext::String
    const reader::String
    const directories::Directories
    const file::String
    const glob::String
    const metadata::Dict{String, Any}
    names::Vector{String}
end

const DEFAULT_READERS = Dict{String, String}(
    ".csv" => "read_csv",
    ".tsv" => "read_csv",
    ".txt" => "read_csv",
    ".json" => "read_json",
    ".parquet" => "read_parquet",
)

function Experiment(;
        db::Union{Nothing, DuckDB.DB} = nothing,
        pool::DuckDBPool = DuckDBPool(),
        prefix::String,
        name::String,
        ext::String = ".csv",
        reader::String = DEFAULT_READERS[ext],
        directories::Directories = Directories(),
        metadata::Dict{String, Any} = Dict{String, Any}()
    )

    path = mkpath(joinpath(prefix, name))

    directories = Directories(path, directories)

    file = joinpath(path, "$name.parquet")
    glob = joinpath(directories.source, "*" * ext)

    db = @something db DuckDB.DB(joinpath(path, "$name.duckdb"))
    repository =  Repository(db, pool)

    return Experiment(repository, prefix, name, ext, reader, directories, file, glob, metadata, String[])
end

function init!(ex::Experiment)
    if isempty(glob(ex.glob))
        throw(ArgumentError("No suitable file found in '$(ex.directories.source)'"))
    end

    if !isfile(ex.file)
        write_parquet(ex)
    end

    define_source_table(ex)
    register_subtable_names!(ex)

    return ex
end

function write_parquet(ex::Experiment)
    query = """
    COPY (
        SELECT * EXCLUDE filename, parse_filename(filename, true) AS _name
        FROM $(ex.reader)('$(ex.glob)', union_by_name = true, filename = true)
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
