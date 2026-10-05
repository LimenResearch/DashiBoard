# The smallest extension there is: one transform, registered the way a real one registers its
# models and funnels. What the launcher's tests load.
module TestExtension

using StreamlinerCore: StreamlinerCore

double(x) = 2 .* x

const DEFAULT_PARSER = StreamlinerCore.Parser(transforms = Dict{String, Any}("double" => double))

end
