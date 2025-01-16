# Shorthands

const StringDict = Dict{String, Any}
const SymbolDict = Dict{Symbol, Any}

const Maybe{T} = Union{Nothing, T}

# Helper to convert lists (as one has in TOML / BSON) to tuples

tuplify_list(v) = v isa AbstractVector ? Tuple(v) : v

# Code from Flux.jl to avoid depending on internals
expand(_, x::Tuple) = x
expand(N, x::Int) = ntuple(Returns(x), N)

function get_outputshape(layer, sh::Shape)
    size = sh.shape..., sh.features
    shape..., features, _ = Flux.outputsize(layer, size, padbatch = true)
    return Shape(shape, features)
end

get_rng(::Nothing = nothing) = Xoshiro()
get_rng(seed::Integer) = Xoshiro(seed)
