# Basic neural network

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
    inputsize, outputsize = size(templates.input), size(templates.target)
    model, _... = chain(b.model, inputsize; outputsize)
    return Basic(; model)
end

basic(components::Config) = architecture(BasicSpec, components)
