function json_schema(key::AbstractString, args...)
    spec = get_spec(key)
    return spec.schema(spec.settings, key, args...)
end

function split_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    properties = Dict(
        "type" => Dict("const" => key),
        "order_by" => json_vars(vars, min = 1),
        "group_by" => json_vars(vars),
        "method" => json_enum(keys(SPLITTING_METHODS)),
        "output" => json_string(min = 1),
    )
    return Dict(
        "type" => "object",
        "properties" => properties,
        "allOf" => conditional_options_schemas(SPLITTING_METHODS),
        "required" => ["type", "order_by", "method", "output"]
    )
end

const SPLIT_SPEC = CardSpec(split_card_schema, type = SplitCard, label = "Split")

function window_function_card_schema(::Any, key::AbstractString, vars::AbstractVector)
    properties = Dict(
        "type" => Dict("const" => key),
        "order_by" => json_vars(vars, min = 1),
        "group_by" => json_vars(vars),
        "method" => json_enum(keys(WINDOW_FUNCTIONS)),
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
        "method" => json_enum(keys(RESCALERS)),
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
        "method" => json_enum(keys(CLUSTERING_METHODS)),
        "inputs" => json_vars(vars, min = 1),
        "weights" => nullable(json_var(vars)),
        "partition" => nullable(json_var(vars)),
        "output" => json_string(min = 1)
    )
    return Dict(
        "type" => "object",
        "properties" => properties,
        "allOf" => conditional_options_schemas(CLUSTERING_METHODS),
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
        "method" => json_enum(keys(PROJECTION_METHODS)),
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
        "distribution" => json_enum(keys(NOISE_MODELS)),
        "link" => nullable(json_enum(keys(LINK_TYPES))),
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
        "method" => json_enum(keys(INTERPOLATION_METHODS)),
        "input" => json_var(vars),
        "targets" => json_vars(vars, min = 1),
        "partition" => nullable(json_var(vars)),
        "suffix" => json_string(min = 1)
    )

    return Dict(
        "type" => "object",
        "properties" => properties,
        "allOf" => conditional_options_schemas(INTERPOLATION_METHODS),
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
        "method" => json_enum(keys(TEMPORAL_PREPROCESSING_METHODS)),
        "input" => json_var(vars),
        "n_components" => json_integer(min = 1),
        "lambda" => json_number(exclusive_min = 0),
        "suffix" => json_string(min = 1)
    )

    return Dict(
        "type" => "object",
        "properties" => properties,
        "allOf" => conditional_options_schemas(TEMPORAL_PREPROCESSING_METHODS),
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
    properties = StringDict(
        "type" => Dict("const" => key),
        "funnel" => json_enum(keys(PARSER[].funnels)), # TODO: implement json schema for funnels too
        "partition" => nullable(json_var(vars)),
        "suffix" => json_string(min = 1)
    )

    model_dir = isassigned(MODEL_DIR) ? MODEL_DIR[] : nothing
    training_dir = isassigned(TRAINING_DIR) ? TRAINING_DIR[] : nothing

    conditions = StringDict[]

    if isnothing(model_dir)
        properties["model_metadata"] = Dict("type" => "object")
        push!(required, "model_metadata")
    else
        model_configs = available_streamliner_configs(model_dir)
        conditional_model_schemas = conditional_streamliner_schemas(
            model_dir, model_configs, "model"
        )
        append!(conditions, conditional_model_schemas)
        properties["model"] = json_enum(model_configs)
    end

    if isnothing(training_dir)
        properties["training_metadata"] = Dict("type" => "object")
        push!(required, "training_metadata")
    else
        training_configs = available_streamliner_configs(training_dir)
        conditional_training_schemas = conditional_streamliner_schemas(
            training_dir, training_configs, "training"
        )
        append!(conditions, conditional_training_schemas)
        properties["training"] = json_enum(training_configs)
    end

    return StringDict(
        "type" => "object",
        "properties" => properties,
        "required" => required,
        "allOf" => conditions
    )
end

const STREAMLINER_SPEC = CardSpec(
    streamliner_card_schema,
    type = StreamlinerCard,
    label = "Streamliner"
)

function wild_card_schema(settings::Any, key::AbstractString, vars::AbstractVector)
    required = String["type", "inputs"]

    properties = Dict{String, Any}(
        "type" => Dict("const" => key),
        "inputs" => json_vars(vars)
    )

    if settings.needs_order
        push!(required, "order_by")
        properties["order_by"] = json_vars(vars, min = 1)
    end

    if settings.needs_targets
        push!(required, "targets")
        push!(required, "suffix")
        properties["targets"] = json_vars(vars, min = 1)
        properties["suffix"] = json_string(min = 1)
        anyOf = Any[]
    else
        anyOf = Any[
            Dict(
                "required" => ["output"],
                "properties" => Dict("output" => json_var(vars))
            ),
            Dict(
                "required" => ["outputs"],
                "properties" => Dict("outputs" => json_vars(vars, min = 1))
            ),
        ]
    end

    if settings.allows_weights
        properties["weights"] = nullable(json_var(vars))
    end

    if settings.allows_partition
        properties["partition"] = nullable(json_var(vars))
    end

    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required,
        "anyOf" => anyOf
    )
end

function register_wild_card(key::Symbol; label::AbstractString, settings::WildCardSettings)
    type = WildCard{key}
    spec = CardSpec(wild_card_schema; type, label, settings)
    return register_card(string(key) => spec)
end
