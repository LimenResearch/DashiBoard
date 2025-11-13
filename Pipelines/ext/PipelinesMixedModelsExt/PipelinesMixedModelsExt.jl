module PipelinesMixedModelsExt

using Pipelines: MixedModelCard, MIXED_MODEL_CARD_CONFIG, register_card, Pipelines
using MixedModels: GeneralizedLinearMixedModel

Pipelines.model_type(::MixedModelCard) = GeneralizedLinearMixedModel

function __init__()
    return register_card(MIXED_MODEL_CARD_CONFIG)
end

end
