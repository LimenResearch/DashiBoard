module DashiBase

using StructUtils: StructUtils, @defaults, @kwarg, fielddefaults, fieldtags
using JSON: JSON
using Base: Fix1
using Base.ScopedValues: @with

const StringDict = Dict{String, Any}
const SymbolDict = Dict{Symbol, Any}

const Maybe{T} = Union{T, Nothing}

map_into(f::F, ::Type{T}, x) where {F, T} = (y::T = T(x); map!(f, values(y)); y)

function get_metadata end

include("style.jl")
include("IR.jl")
include("auto_IR.jl")
include("definitions.jl")
include("methods.jl")
include("json_rpc.jl")

end # module DashiBase
