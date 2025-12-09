# Basic Neural Network

@kwdef struct Basic{M}
    model::M
end

@layer Basic

function (b::Basic)(x)
    prediction = b.model(x.input)
    return merge(x, (; prediction))
end

# constructor

struct BasicSpec
    model::Vector{Any}
end

function instantiate(b::BasicSpec, templates)
    input = Shape(templates.input)
    output = Shape(templates.target)
    model, _ = chain(b.model, input, output)
    return Basic(; model)
end

basic(components::AbstractDict) = architecture(BasicSpec, components)
