# Type to encode selection of fields

const SymbolTuple{N} = NTuple{N, Symbol}

# Template to encode eltype and size of array

# Type for `templates` dispatch
const Tup = Union{Tuple, NamedTuple}

struct Template{T, N}
    size::NTuple{N, Int}
end

Template{T}(size::NTuple{N, Int}) where {T, N} = Template{T, N}(size)

"""
    Template(::Type{T}, size::NTuple{N, Int}) where {T, N}

Create an object of type `Template`.
It represents arrays with eltype `T` and size `size`.
Note that `size` does not include the minibatch dimension.
"""
Template(::Type{T}, size::NTuple{N, Int}) where {T, N} = Template{T, N}(size)

Base.size(t::Template) = t.size
Base.eltype(::Type{Template{T, N}}) where {T, N} = T

"""
    AbstactData{N}

Abstract type representing streamers of `N` datasets.
In general, StreamlinerCore will use `N = 1` to validate and evaluate trained models
and `N = 2` to train models via a training and a validation datasets.

Subtypes of `AbstractData` are meant to implement the following methods:
- [`stream`](@ref),
- [`get_templates`](@ref),
- [`get_metadata`](@ref),
- [`get_nsamples`](@ref).
"""
abstract type AbstractData{N} end

@enumx DataPartition training = 1 validation = 2

@kwdef struct Streaming
    device::AbstractDevice
    batchsize::Maybe{Int}
    shuffle::Bool = false
    rng::AbstractRNG = get_rng()
end

@parsable Streaming

get_device(config::AbstractDict) = PARSER[].devices[get(config, :device, "cpu")]()
get_batchsize(config::AbstractDict) = get(config, :batchsize, nothing)
get_shuffle(config::AbstractDict) = get(config, :shuffle, false)

"""
    Streaming(parser::Parser, metadata::AbstractDict)

    Streaming(parser::Parser, path::AbstractString, [vars::AbstractDict])

Create a `Streaming` object from a configuration dictionary `metadata` or, alternatively,
from a configuration dictionary stored at `path` in TOML format.
The optional argument `vars` is a dictionary of variables the can be used to
fill the template given in `path`.

The `parser::`[`Parser`](@ref) handles conversion from configuration variables to julia objects.
"""
function Streaming(parser::Parser, metadata::AbstractDict)
    config = to_config(metadata)
    return @with PARSER => parser begin
        device = get_device(config)
        batchsize = get_batchsize(config)
        shuffle = get_shuffle(config)
        Streaming(; device, batchsize, shuffle)
    end
end

"""
    stream(f, data::AbstractData, partition::Integer, streaming::Streaming)

Stream `partition` of `data` by batches of `batchsize` on a given `device`.
Return the result of applying `f` on the resulting batch iterator.
Shuffling is optional and controlled by `shuffle` (boolean)
and by the random number generator `rng`.

The options `device`, `batchsize`, `shuffle`, `rng` are passed via the configuration
struct `streaming::Streaming`. See also [`Streaming`](@ref).
"""
function stream end

function stream(f, data::AbstractData{1}, streaming::Streaming)
    return stream(f, data, 1, streaming)
end

function stream(f, data::AbstractData, partition::DataPartition.T, streaming::Streaming)
    return stream(f, data, Int(partition), streaming)
end

function stream(f, data::AbstractData, partition::Int, streaming::Streaming)
    throw(MethodError(stream, (f, data, partition, streaming)))
end

"""
    ingest(data::AbstractData{1}, eval_stream, select)

Ingest output of `evaluate` into a suitable database, tensor or iterator.
`select` determines which fields of the model output to keep.
"""
function ingest end

"""
    get_templates(data::AbstractData)

Extract templates for `data`.
Templates encode type and size of the arrays that `data` will [`stream`](@ref).
See also [`Template`](@ref)
"""
function get_templates end

"""
    get_metadata(x)::Dict{String, Any}

Extract metadata for `x`.
`metadata` should be a dictionary of information that identifies `x` univoquely.
`get_metadata` has methods for [`AbstractData`](@ref), [`Model`](@ref), and [`Training`](@ref).
"""
function get_metadata end

get_metadata(d::AbstractDict) = d

"""
    get_nsamples(data::AbstractData{N})::NTuple{N, Int} where {N}

Return number of samples for `data`.
"""
function get_nsamples end

get_nsamples(data::AbstractData{1}) = get_nsamples(data, 1)
get_nsamples(data::AbstractData, partition) = get_nsamples(data::AbstractData, Int(partition))
get_nsamples(data::AbstractData, partition::Int) = throw(MethodError(get_nsamples, (data, partition)))

struct Data{N, S, T} <: AbstractData{N}
    streams::NTuple{N, S}
    templates::T
    metadata::StringDict
end

function Data{N}(streams::NTuple{N, S}, templates::T, metadata::AbstractDict) where {N, S, T}
    return Data{N, S, T}(streams, templates, metadata)
end

# work around https://github.com/FluxML/Flux.jl/issues/2592
to_device(device::AbstractDevice, x) = invoke(device, Tuple{Any}, x)

function stream(f, data::Data, partition::Int, streaming::Streaming)
    (; device, batchsize, shuffle, rng) = streaming
    batches = if isnothing(batchsize)
        (device(data.streams[partition]),)
    else
        dl = DataLoader(data.streams[partition]; batchsize, rng, shuffle)
        to_device(device, dl)
    end
    return f(batches)
end

ingest(::Data{1}, stream, select) = Iterators.map(NamedTuple{select}, stream)

get_templates(data::Data) = data.templates

get_metadata(data::Data) = data.metadata

get_nsamples(data::Data, partition::Int) = numobs(data.streams[partition])
