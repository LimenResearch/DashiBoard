function json_schema(key::AbstractString, args...)
    spec = get_spec(key)
    return spec.schema(spec.settings, key, args...)
end

function split_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    properties = Dict(
        "type" => Dict("const" => key),
        "order_by" => json_vars(vars, min = 1),
        "group_by" => json_vars(vars),
        "method" => json_var(keys(SPLITTING_METHODS)),
        "method_options" => Dict("type" => "object"), # TODO: validate correct keywords
        "output" => json_string(min = 1),
    )
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => ["type", "order_by", "method", "output"]
    )
end

const SPLIT_SPEC = CardSpec(split_card_schema, type = SplitCard, label = "Split")

function window_function_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    properties = Dict(
        "type" => Dict("const" => key),
        "order_by" => json_vars(vars, min = 1),
        "group_by" => json_vars(vars),
        "method" => json_var(keys(WINDOW_FUNCTIONS)),
        "output" => json_string(min = 1),
    )
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => ["type", "order_by", "method", "output"]
    )
end

const WINDOW_FUNCTION_SPEC = CardSpec(
    window_function_card_schema,
    type = WindowFunctionCard,
    label = "Window Function"
)

function rescale_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    properties = Dict(
        "type" => Dict("const" => key),
        "method" => json_var(keys(RESCALERS)),
        "group_by" => json_vars(vars),
        "inputs" => json_vars(vars),
        "targets" => json_vars(vars),
        "partition" => nullable(json_var(vars)),
        "suffix" => json_string(min = 1),
        "target_suffix" => nullable(json_string(min = 1))
    )
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => ["type", "method", "inputs"]
    )
end

const RESCALE_SPEC = CardSpec(
    rescale_card_schema,
    type = RescaleCard,
    label = "Rescale"
)

function cluster_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    properties = Dict(
        "type" => Dict("const" => key),
        "method" => json_var(keys(CLUSTERING_METHODS)),
        "method_options" => Dict("type" => "object"), # TODO: validate correct keywords
        "inputs" => json_vars(vars, min = 1),
        "weights" => nullable(json_var(vars)),
        "partition" => nullable(json_var(vars)),
        "output" => json_string(min = 1)
    )
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => ["type", "method", "inputs"]
    )
end

const CLUSTER_SPEC = CardSpec(
    cluster_card_schema,
    type = ClusterCard,
    label = "Cluster"
)

function dimensionality_reduction_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    properties = Dict(
        "type" => Dict("const" => key),
        "method" => json_var(keys(PROJECTION_METHODS)),
        "inputs" => json_vars(vars, min = 1),
        "partition" => nullable(json_var(vars)),
        "n_components" => json_integer(min = 1),
        "output" => json_string(min = 1)
    )
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => ["type", "method", "inputs", "n_components"]
    )
end

const DIMENSIONALITY_REDUCTION_SPEC = CardSpec(
    dimensionality_reduction_card_schema,
    type = DimensionalityReductionCard,
    label = "Dimensionality Reduction"
)

function abstract_glm_card_schema(
        ::Type{C}, key::AbstractString, vars::AbstractVector
    ) where {C <: AbstractGLMCard}
    required = String["type", "target"]
    properties = Dict{String, Any}(
        "type" => Dict("const" => key),
        "distribution" => json_var(keys(NOISE_MODELS)),
        "link" => nullable(json_var(keys(LINK_TYPES))),
        "partition" => nullable(json_var(vars)),
        "target" => json_var(vars),
        "suffix" => json_string(min = 1)
    )
    if has_grouping_factor(C)
        properties["fixed_effect_terms"] = Dict("type" => "array")
        properties["random_effect_terms"] = Dict("type" => "array")
        properties["grouping_factor"] = json_var(vars)
        append!(required, ["fixed_effect_terms", "random_effect_terms", "grouping_factor"])
    else
        properties["inputs"] = Dict("type" => "array")
        append!(required, ["inputs"])
    end

    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required
    )
end

function glm_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    return abstract_glm_card_schema(GLMCard, key, vars)
end

const GLM_SPEC = CardSpec(
    glm_card_schema,
    type = GLMCard,
    label = "GLM"
)

function mixed_model_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    return abstract_glm_card_schema(MixedModelCard, key, vars)
end

const MIXED_MODEL_SPEC = CardSpec(
    mixed_model_card_schema,
    type = MixedModelCard,
    label = "Mixed Model"
)

function interp_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    required = String["type", "method", "input", "targets"]
    properties = Dict(
        "type" => Dict("const" => key),
        "method" => json_var(keys(INTERPOLATION_METHODS)),
        "method_options" => Dict("type" => "object"), # TODO: validate correct keywords
        "input" => json_var(vars),
        "targets" => json_vars(vars, min = 1),
        "partition" => nullable(json_var(vars)),
        "suffix" => json_string(min = 1)
    )

    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required
    )
end

const INTERP_SPEC = CardSpec(
    interp_card_schema,
    type = InterpCard,
    label = "Interpolation"
)

function gaussian_encoding_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    required = String["type", "input", "n_components"]
    properties = Dict(
        "type" => Dict("const" => key),
        "method" => json_var(keys(TEMPORAL_PREPROCESSING_METHODS)),
        "method_options" => Dict("type" => "object"), # TODO: validate correct keywords
        "input" => json_var(vars),
        "n_components" => json_integer(min = 1),
        "lambda" => json_number(exclusive_min = 0),
        "suffix" => json_string(min = 1)
    )

    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required
    )
end

const GAUSSIAN_ENCODING_SPEC = CardSpec(
    gaussian_encoding_card_schema,
    type = GaussianEncodingCard,
    label = "Gaussian Encoding"
)

function streamliner_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    required = String["type", "model", "training"]
    properties = Dict(
        "type" => Dict("const" => key),
        "model_options" => Dict("type" => "object"), # TODO: validate correct keywords
        "training_options" => Dict("type" => "object"), # TODO: validate correct keywords
        "funnel" => json_var(keys(PARSER[].funnels)), # TODO: implement json schema for funnels too
        "partition" => nullable(json_var(vars)),
        "suffix" => json_string(min = 1)
    )

    model_schema = Dict(
        "anyOf" => [
            Dict(
                "required" => ["model_metadata"],
                "properties" => Dict(
                    "model_metadata" => Dict("type" => "object")
                )
            ),
            Dict(
                "properties" => Dict(
                    "model" => json_var(available_streamliner_model_configs())
                )
            ),
        ]
    )

    training_schema = Dict(
        "anyOf" => [
            Dict(
                "required" => ["training_metadata"],
                "properties" => Dict(
                    "training_metadata" => Dict("type" => "object")
                )
            ),
            Dict(
                "properties" => Dict(
                    "training" => json_var(available_streamliner_training_configs())
                )
            ),
        ]
    )

    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required,
        "allOf" => [model_schema, training_schema]
    )
end

const STREAMLINER_SPEC = CardSpec(
    streamliner_card_schema,
    type = StreamlinerCard,
    label = "Streamliner"
)
