module PipelinesMixedModelsExt

using Pipelines: MixedModelCard, Pipelines
using MixedModels: GeneralizedLinearMixedModel

Pipelines.model_type(::MixedModelCard) = GeneralizedLinearMixedModel

end
