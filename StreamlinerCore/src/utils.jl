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

# Funneled data utils

filter_partition(partition::AbstractString, n::Integer = 1) = Where(Get(partition) .== n)

function filter_partition(::Nothing, n::Integer = 1)
    if n != 1
        throw(ArgumentError("Data has not been split"))
    end
    return identity
end

join_names(args...) = join(args, "_")
