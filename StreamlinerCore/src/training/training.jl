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

@parsable Training

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

parse_iterations(metadata::AbstractDict) = get(metadata, "iterations", 1000)
parse_seed(metadata::AbstractDict) = get(metadata, "seed", nothing)
parse_options(metadata::AbstractDict) = make(SymbolDict, get_config(metadata, "options"))

"""
    Training(parser::Parser, metadata::AbstractDict)

    Training(parser::Parser, path::AbstractString, [vars::AbstractDict])

Create a `Training` object from a configuration dictionary `metadata` or, alternatively,
from a configuration dictionary stored at `path` in TOML format.
The optional argument `vars` is a dictionary of variables the can be used to
fill the template given in `path`.

The `parser::`[`Parser`](@ref) handles conversion from configuration variables to julia objects.
"""
function Training(parser::Parser, metadata::AbstractDict)

    return @with PARSER => parser begin
        optimizer = parse_optimizer(metadata)

        device = parse_device(metadata)
        batchsize = parse_batchsize(metadata)
        shuffle = parse_shuffle(metadata)
        seed = parse_seed(metadata)

        iterations = parse_iterations(metadata)
        schedules = parse_schedules(metadata)
        stoppers = parse_stoppers(metadata)

        options = parse_options(metadata)

        Training(
            metadata, optimizer, device, shuffle, batchsize, iterations,
            schedules, stoppers, options, seed
        )
    end
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
