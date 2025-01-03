struct Model{L, M <: Tuple, R <: Tuple}
    metadata::StringDict
    architecture::Any
    loss::L
    metrics::M
    regularizations::R
    context::SymbolDict
    seed::Maybe{Int}
end

@parsable Model

const ModelPair{L, M <: Tuple, R <: Tuple, T} = Pair{Model{L, M, R}, T}

get_metadata(model::Model) = model.metadata

Model(m::Model) = m

"""
    Model(parser::Parser, metadata::AbstractDict)

    Model(parser::Parser, path::AbstractString, [vars::AbstractDict])

Create a `Model` object from a configuration dictionary `metadata` or, alternatively,
from a configuration dictionary stored at `path` in TOML format.
The optional argument `vars` is a dictionary of variables the can be used to
fill the template given in `path`.

The `parser::`[`Parser`](@ref) handles conversion from configuration variables to julia objects.

Given a `model::Model` object, use `model(data)` where `data::`[`AbstractData`](@ref)
to instantiate the corresponding neural network or machine.
"""
function Model(parser::Parser, metadata::AbstractDict)
    config = Config(metadata)
    return @with PARSER => parser begin
        architecture = get_architecture(config)
        loss = get_loss(config)
        metrics = get_metrics(config)
        regularizations = get_regularizations(config)
        context = get_context(config)
        seed = get(config, :seed, nothing)
        Model(metadata, architecture, loss, metrics, regularizations, context, seed)
    end
end

function (model::Model)(templates::Tup)
    # Set the seed before initializing the model
    isnothing(model.seed) || seed!(model.seed)
    return @with MODEL_CONTEXT => model.context instantiate(model.architecture, templates)
end

(model::Model)(data::AbstractData) = model(get_templates(data))
