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

function _to_dict(t::Template)
    elt, sz = eltype(t), size(t)
    return StringDict("eltype" => string(elt), "size" => collect(sz))
end

templates2dict(ts::NamedTuple) = StringDict(String(k) => _to_dict(v) for (k, v) in pairs(ts))

function _to_template(d::AbstractDict)
    T = getproperty(Base, Symbol(d["eltype"]))
    size = Tuple(d["size"])
    return Template{T}(size)
end

dict2templates(d::AbstractDict) = NamedTuple(Symbol(k) => _to_template(v) for (k, v) in pairs(d))

"""
    AbstactData{N}

Abstract type representing streamers of `N` datasets.
In general, StreamlinerCore will use `N = 1` to validate and evaluate trained models
and `N = 2` to train models via a training and a validation datasets.

Subtypes of `AbstractData` are meant to implement the following methods:
- [`stream`](@ref),
- [`get_templates`](@ref),
- [`get_metadata`](@ref),
- [`get_summary`](@ref) (optional).
"""
abstract type AbstractData{N} end

"""
    stream(f, data::AbstractData{N}, partition::Integer; batchsize, device, rng::RNG = get_rng(), shuffle = false) where {N}

Stream `partition` of `data` by batches of `batchsize` on a given `device`.
Return the result of applying `f` on the resulting batch iterator.
Shuffling is optional and controlled by `shuffle` (boolean)
and by the random number generator `rng`.
"""
function stream end

function stream(f, data::AbstractData{1}; options...)
    return stream(f, data, 1; options...)
end

function stream(f, data::AbstractData, partition; options...)
    return stream(f, data, Int(partition); options...)
end

function stream(f, data::AbstractData, partition::Int; options...)
    throw(MethodError(stream, (f, data, partition)))
end

@enumx DataPartition training = 1 validation = 2

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
`metadata` should be a dictionary of information that identifies `x`
univoquely.
After training, it will be stored in the MongoDB together.
`get_metadata` has methods for [`AbstractData`](@ref), [`Model`](@ref), and [`Training`](@ref).
"""
function get_metadata end

"""
    get_summary(data::AbstractData)::Dict{String, Any}

Extract summary for `data`.
`summary` should be a dictionary of summary statistics for `data`.
Common choices of statistics to report are mean and standard deviation,
as well as unique values for categorical variables.
"""
get_summary(::AbstractData) = StringDict()

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

function stream(
        f, data::Data, partition::Int;
        batchsize, device, rng::AbstractRNG = get_rng(), shuffle::Bool = false
    )
    batches = if isnothing(batchsize)
        (device(data.streams[partition]),)
    else
        Iterators.map(device, DataLoader(data.streams[partition]; batchsize, rng, shuffle))
    end
    return f(batches)
end

# TODO: consider concatenating along the batch dimension
ingest(::Data{1}, stream, select::SymbolTuple) = Iterators.map(NamedTuple{select}, stream)

get_templates(data::Data) = data.templates

get_metadata(data::Data) = data.metadata

get_nsamples(data::Data, partition::Int) = numobs(data.streams[partition])
