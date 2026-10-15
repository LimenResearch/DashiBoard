module DashiBase

using StructUtils: StructUtils, @kwarg, fielddefaults, fieldtags
using JSON: JSON
using Base: Fix1
using Base.ScopedValues: @with

const StringDict = Dict{String, Any}
const SymbolDict = Dict{Symbol, Any}

const Maybe{T} = Union{T, Nothing}

function get_metadata end

include("style.jl")
include("IR.jl")
include("auto_IR.jl")
include("definitions.jl")
include("methods.jl")
include("json_rpc.jl")

end # module DashiBase
