module PipelinesMixedModelsExt

using Pipelines:
    AbstractPrimaryKey, train_glm,
    MixedModelCard, MIXED_MODEL_SPEC,
    register_card, Pipelines
using MixedModels: LinearMixedModel, GeneralizedLinearMixedModel, RandomEffectsTerm

Pipelines.israndomeffect(t) = t isa RandomEffectsTerm

function Pipelines._train(gc::MixedModelCard, t, ::AbstractPrimaryKey)
    weights = isnothing(gc.weights) ? nothing : t[gc.weights]
    return train_glm(gc, t, LinearMixedModel, GeneralizedLinearMixedModel; weights)
end

function __init__()
    return register_card("mixed_model" => MIXED_MODEL_SPEC)
end

end
