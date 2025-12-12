# Basic Neural Network

struct BasicSpec
    model::Vector{Any}
end

function basic_forward(modules, x)
    (; model) = modules
    prediction = model(x.input)
    return merge(x, (; prediction))
end

function instantiate(b::BasicSpec, templates)
    input = Shape(templates.input)
    output = Shape(templates.target)
    model, _ = chain(b.model, input, output)
    modules = (; model)
    return Architecture(:Basic, basic_forward, modules)
end

basic(components::AbstractDict) = architecture(BasicSpec, components)
