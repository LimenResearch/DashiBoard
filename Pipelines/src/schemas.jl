function json_schema(key::AbstractString, args...)
    type = get_spec(key).type
    return _json_schema(type, key, args...)
end

const SPLIT_SPEC = CardSpec(
    type = SplitCard,
    label = "Split",
    needs_order = true,
    needs_targets = false,
    allows_weights = false,
    allows_partition = false
)

function _json_schema(::Type{SplitCard}, key::AbstractString, vars::AbstractVector)
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

const WINDOW_FUNCTION_SPEC = CardSpec(
    type = WindowFunctionCard,
    label = "Window Function",
    needs_order = true,
    needs_targets = false,
    allows_weights = false,
    allows_partition = false
)

function _json_schema(::Type{WindowFunctionCard}, key::AbstractString, vars::AbstractVector)
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

const RESCALE_SPEC = CardSpec(
    type = RescaleCard,
    label = "Rescale",
    needs_order = false,
    needs_targets = false,
    allows_weights = false,
    allows_partition = true
)

function _json_schema(::Type{RescaleCard}, key::AbstractString, vars::AbstractVector)
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

const CLUSTER_SPEC = CardSpec(
    type = ClusterCard,
    label = "Cluster",
    needs_order = false,
    needs_targets = false,
    allows_weights = true,
    allows_partition = true
)

function _json_schema(::Type{ClusterCard}, key::AbstractString, vars::AbstractVector)
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

const DIMENSIONALITY_REDUCTION_SPEC = CardSpec(
    type = DimensionalityReductionCard,
    label = "Dimensionality Reduction",
    needs_order = false,
    needs_targets = false,
    allows_weights = false,
    allows_partition = true
)

function _json_schema(::Type{DimensionalityReductionCard}, key::AbstractString, vars::AbstractVector)
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

const GLM_SPEC = CardSpec(
    type = GLMCard,
    label = "GLM",
    needs_order = false,
    needs_targets = true,
    allows_weights = true,
    allows_partition = true
)

const MIXED_MODEL_SPEC = CardSpec(
    type = MixedModelCard,
    label = "Mixed Model",
    needs_order = false,
    needs_targets = true,
    allows_weights = true,
    allows_partition = true
)

function _json_schema(::Type{C}, key::AbstractString, vars::AbstractVector) where {C <: AbstractGLMCard}
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

const INTERP_SPEC = CardSpec(
    type = InterpCard,
    label = "Interpolation",
    needs_order = false,
    needs_targets = true,
    allows_weights = false,
    allows_partition = true
)

function _json_schema(::Type{InterpCard}, key::AbstractString, vars::AbstractVector)
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

const GAUSSIAN_ENCODING_SPEC = CardSpec(
    type = GaussianEncodingCard,
    label = "Gaussian Encoding",
    needs_order = false,
    needs_targets = false,
    allows_weights = false,
    allows_partition = false
)

function _json_schema(::Type{GaussianEncodingCard}, key::AbstractString, vars::AbstractVector)
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

const STREAMLINER_SPEC = CardSpec(
    type = StreamlinerCard,
    label = "Streamliner",
    needs_order = true,
    needs_targets = true,
    allows_weights = false,
    allows_partition = true
)

function _json_schema(::Type{StreamlinerCard}, key::AbstractString, vars::AbstractVector)
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
