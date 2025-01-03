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

function Streaming(
        training::Training;
        shuffle::Bool = training.shuffle,
        rng::AbstractRNG = get_rng(training.seed)
    )
    return Streaming(; training.device, training.batchsize, shuffle, rng)
end

struct TrainingState{T}
    optimizer::T
    stoppers::Vector{Any}
end

const TrainingPair{T} = Pair{Training, TrainingState{T}}

get_metadata(training::Training) = training.metadata

get_iterations(config::Config) = get(config, :iterations, 1000)
get_seed(config::Config) = get(config, :seed, nothing)
get_options(config::Config) = SymbolDict(config.options)

"""
    Training(parser::Parser, metadata::AbstractDict)

Create a `Training` object from a configuration dictionary `metadata`.
The `parser::`[`Parser`](@ref) handles conversion from configuration variables to julia objects.
"""
function Training(parser::Parser, metadata::AbstractDict)
    config = Config(metadata)

    return @with PARSER => parser begin
        optimizer = get_optimizer(config)

        device = get_device(config)
        batchsize = get_batchsize(config)
        shuffle = get_shuffle(config)
        seed = get_seed(config)

        iterations = get_iterations(config)
        schedules = get_schedules(config)
        stoppers = get_stoppers(config)

        options = get_options(config)

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

function is_batched(training::Training)
    (; optimizer, options, schedules, batchsize) = training

    if optimizer isa AbstractRule
        if !isempty(options)
            throw(ArgumentError("No `options` keywords allowed for $(optimizer)"))
        end
        return true
    else
        if !isempty(schedules)
            throw(ArgumentError("No schedules allowed for $(optimizer)"))
        end
        if !isnothing(batchsize)
            throw(ArgumentError("No batchsize allowed for $(optimizer)"))
        end
        return false
    end
end

setup(opt::AbstractRule, device_m) = Flux.setup(opt, device_m)

setup(opt, _) = opt