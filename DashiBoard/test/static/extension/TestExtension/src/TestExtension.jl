# The smallest extension there is: one transform and one funnel, registered the way a real one
# registers its models and funnels. What the launcher's tests load.
module TestExtension

using StreamlinerCore: StreamlinerCore
using DashiBase: ObjectIR, Property, StringIR

double(x) = 2 .* x

# A funnel that describes itself through a method of its own, as a funnel wrapping another does:
# the server has to see methods an extension defines, not only the entries it registers.
struct TestFunnel <: StreamlinerCore.Funnel end

StreamlinerCore.funnel_IR(::Type{TestFunnel}) = ObjectIR(properties = [Property("marker" => StringIR(); required = false)])

const DEFAULT_PARSER = StreamlinerCore.Parser(
    transforms = Dict{String, Any}("double" => double),
    funnels = Dict{String, Any}("test" => TestFunnel),
)

end
