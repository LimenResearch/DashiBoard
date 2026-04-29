# Shorthands

const StringDict = Dict{String, Any}
const SymbolDict = Dict{Symbol, Any}

const Maybe{T} = Union{T, Nothing}

# Helper to convert lists (as one has in TOML / BSON) to tuples

tuplify_list(v) = v isa AbstractVector ? Tuple(v) : v

get_rng(::Nothing = nothing) = Xoshiro()
get_rng(seed::Integer) = Xoshiro(seed)

# Helper get methods

get_config(d::AbstractDict, k::AbstractString) = get(d, k, StringDict())

get_configs(d::AbstractDict, k::AbstractString) = get(d, k, StringDict[])

# Default directory structure

output_path(dir::AbstractString) = joinpath(dir, "output.jld2")

stats_path(dir::AbstractString) = joinpath(dir, "stats.bin")

# Code from Flux.jl to avoid depending on internals

expand(_, x::Tuple) = x
expand(N, x::Int) = ntuple(Returns(x), N)
