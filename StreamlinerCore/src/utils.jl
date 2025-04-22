# Shorthands

const StringDict = Dict{String, Any}
const SymbolDict = Dict{Symbol, Any}

const Maybe{T} = Union{Nothing, T}

# Helper to convert lists (as one has in TOML / BSON) to tuples

tuplify_list(v) = v isa AbstractVector ? Tuple(v) : v

get_rng(::Nothing = nothing) = Xoshiro()
get_rng(seed::Integer) = Xoshiro(seed)

to_config(d::AbstractDict) = SymbolDict(Symbol(k) => to_config(v) for (k, v) in pairs(d))
to_config(v::AbstractVector) = map(to_config, v)
to_config(x) = x

function pop(d::AbstractDict, keys...)
    d′ = copy(d)
    vals = map(key -> key isa Pair ? pop!(d′, key...) : pop!(d′, key), keys)
    return d′, vals...
end

get_config(d::AbstractDict{Symbol}, k::Symbol) = get(d, k, SymbolDict())

get_configs(d::AbstractDict{Symbol}, k::Symbol) = get(d, k, SymbolDict[])

# Default directory structure

output_path(dir::AbstractString) = joinpath(dir, "output.jld2")

stats_path(dir::AbstractString) = joinpath(dir, "stats.bin")

# Code from Flux.jl to avoid depending on internals

expand(_, x::Tuple) = x
expand(N, x::Int) = ntuple(Returns(x), N)

# helper to acces memory from array 
get_memory(a::Array) = a.mem.ref
