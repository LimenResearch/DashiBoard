struct Training
    metadata::StringDict
    optimizer::Any
    device::Any
    shuffle::Bool
    batchsize::Maybe{Int}
    iterations::Int
    schedules::SymbolDict
    stoppers::Vector{Stopper}
    options::SymbolDict
    seed::Maybe{Int}
end

struct TrainingState{T}
    optimizer::T
    stoppers::Vector{Any}
end

const TrainingPair{T} = Pair{Training, TrainingState{T}}

get_metadata(training::Training) = training.metadata

"""
    Training(parser::Parser, metadata::AbstractDict)

Create a `Training` object from a configuration dictionary `metadata`.
The `parser::`[`Parser`](@ref) handles conversion from configuration variables to julia objects.
"""
function Training(parser::Parser, metadata::AbstractDict)
    config = Config(metadata)

    return @with PARSER => parser begin
        optimizer = get_optimizer(config)

        device = PARSER[].devices[get(config, :device, "cpu")]

        batchsize = get(config, :batchsize, nothing)
        iterations = get(config, :iterations, 1000)

        schedules = get_schedules(config)
        stoppers = get_stoppers(config)

        options = SymbolDict(config.options)
        seed = get(config, :seed, nothing)

        shuffle = get(config, :shuffle, true)

        Training(
            metadata, optimizer, device, shuffle, batchsize, iterations,
            schedules, stoppers, options, seed
        )
    end
end

"""
    Training(parser::Parser, path::AbstractString, [vars::AbstractDict])

Create a `Training` object from a configuration dictionary stored at `path`
in TOML format.

The `parser::`[`Parser`](@ref) handles conversion from configuration variables to julia objects.

The optional argument `vars` is a dictionary of variables the can be used to
fill the template given in `path`.

See the `static/training` folder for example configurations.
"""
function Training(parser::Parser, path::AbstractString, vars::Maybe{AbstractDict} = nothing)
    metadata::StringDict = TOML.parsefile(path)
    return Training(parser, replace_variables(metadata, vars))
end
