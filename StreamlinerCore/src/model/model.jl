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

"""
    output_fields(constructor)::Tuple{Vararg{Symbol}}
    output_fields(model::Model)

The fields a model puts in its output, keyed on the architecture's *constructor* — the function
registered in the parser under the model's `name`. Asking the constructor rather than a built
network is what lets a schema describe a model configuration without instantiating it.

An architecture yielding more than a prediction adds a method. The `Model` form looks the
constructor up in the parser in scope, so it has to be asked where that parser is.
"""
output_fields(::Any) = (:prediction,)
output_fields(model::Model) = output_fields(PARSER[].models[model.metadata["name"]])

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
    return @with PARSER => parser begin
        architecture = parse_architecture(metadata)
        loss = parse_loss(metadata)
        metrics = parse_metrics(metadata)
        regularizations = parse_regularizations(metadata)
        context = parse_context(metadata)
        seed = parse_seed(metadata)
        Model(metadata, architecture, loss, metrics, regularizations, context, seed)
    end
end

function (model::Model)(templates::Tup)
    # Set the seed before initializing the model
    isnothing(model.seed) || seed!(model.seed)
    return @with MODEL_CONTEXT => model.context instantiate(model.architecture, templates)
end

(model::Model)(data::AbstractData) = model(get_templates(data))
