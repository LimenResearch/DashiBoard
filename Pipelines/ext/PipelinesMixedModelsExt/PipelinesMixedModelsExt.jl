module PipelinesMixedModelsExt

using Pipelines: train_glm, MixedModelCard, MIXED_MODEL_CARD_CONFIG, register_card, Pipelines
using MixedModels: LinearMixedModel, GeneralizedLinearMixedModel

function Pipelines._train(gc::MixedModelCard, t, ::Any; weights = nothing)
    return train_glm(gc, t, LinearMixedModel, GeneralizedLinearMixedModel; weights)
end

function __init__()
    return register_card(MIXED_MODEL_CARD_CONFIG)
end

end
