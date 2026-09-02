module DashiBase

using StructUtils: StructUtils, @kwarg, fielddefaults, fieldtags
using JSON: JSON

const StringDict = Dict{String, Any}

include("style.jl")
include("IR.jl")
include("auto_IR.jl")

end # module DashiBase
