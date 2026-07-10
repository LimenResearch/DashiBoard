function schema_definitions(variables::AbstractVector)
    variable_schema = json_string(enum = variables)
    variables_schema = json_array(items = JSON_VARIABLE, default = [])
    nonempty_variables_schema = json_array(items = JSON_VARIABLE, minItems = 1)
    return StringDict(
        "variable" => variable_schema,
        "variables" => variables_schema,
        "nonempty_variables" => nonempty_variables_schema,
    )
end

function json_schema(
        key::AbstractString, variables::Any;
        additionalProperties::Bool = false
    )::StringDict
    schema = json_schema(key; additionalProperties)
    schema["\$defs"] = schema_definitions(variables)
    return schema
end

function json_schema(key::AbstractString; additionalProperties::Bool = false)::StringDict
    spec = get_spec(key)
    schema::StringDict = spec.schema(spec.settings, key)
    # set defaults if not provided by card schema implementation
    schema["properties"]["type"] = json_const(key)
    get!(schema, "title", spec.label)
    get!(schema, "additionalProperties", additionalProperties)
    return schema
end

# Card implementations

split_card_schema(::Any, key::AbstractString) = options_schema(SplitCard)

const SPLIT_SPEC = CardSpec(split_card_schema, type = SplitCard, label = "Split")

function window_function_card_schema(::Any, key::AbstractString)
    properties = StringDict(
        "type" => json_const(key),
        "order_by" => JSON_NONEMPTY_VARIABLES,
        "group_by" => JSON_VARIABLES,
        "method" => json_string(enum = keys(WINDOW_FUNCTIONS)),
        "output" => json_string(minLength = 1),
    )
    required = ["order_by", "method", "output"]
    return json_object(; properties, required)
end

const WINDOW_FUNCTION_SPEC = CardSpec(
    window_function_card_schema,
    type = WindowFunctionCard,
    label = "Window Function"
)

function rescale_card_schema(::Any, key::AbstractString)
    properties = StringDict(
        "type" => json_const(key),
        "method" => json_string(enum = keys(RESCALERS)),
        "group_by" => JSON_VARIABLES,
        "inputs" => JSON_VARIABLES,
        "targets" => JSON_VARIABLES,
        "partition" => JSON_VARIABLE,
        "suffix" => json_string(minLength = 1),
        "target_suffix" => json_string(minLength = 1)
    )
    required = ["method", "inputs"]
    return json_object(; properties, required)
end

const RESCALE_SPEC = CardSpec(
    rescale_card_schema,
    type = RescaleCard,
    label = "Rescale"
)

cluster_card_schema(::Any, key::AbstractString) = options_schema(ClusterCard)

const CLUSTER_SPEC = CardSpec(
    cluster_card_schema,
    type = ClusterCard,
    label = "Cluster"
)

dimensionality_reduction_card_schema(::Any, key::AbstractString) = options_schema(DimensionalityReductionCard)

const DIMENSIONALITY_REDUCTION_SPEC = CardSpec(
    dimensionality_reduction_card_schema,
    type = DimensionalityReductionCard,
    label = "Dimensionality Reduction"
)

function abstract_glm_card_schema(
        ::Type{C}, key::AbstractString
    ) where {C <: AbstractGLMCard}
    required = String["target"]
    properties = StringDict(
        "type" => json_const(key),
        "distribution" => json_string(enum = keys(NOISE_MODELS)),
        "link" => json_string(enum = keys(LINK_TYPES)),
        "weights" => JSON_VARIABLE,
        "partition" => JSON_VARIABLE,
        "target" => JSON_VARIABLE,
        "suffix" => json_string(minLength = 1)
    )
    # TODO: stricter formula schema
    if has_grouping_factor(C)
        properties["fixed_effect_terms"] = json_array()
        properties["random_effect_terms"] = json_array()
        properties["grouping_factor"] = JSON_VARIABLE
        append!(required, ["fixed_effect_terms", "random_effect_terms", "grouping_factor"])
    else
        properties["inputs"] = json_array()
        append!(required, ["inputs"])
    end

    return json_object(; properties, required)
end

function glm_card_schema(::Any, key::AbstractString)
    return abstract_glm_card_schema(GLMCard, key)
end

const GLM_SPEC = CardSpec(
    glm_card_schema,
    type = GLMCard,
    label = "GLM"
)

function mixed_model_card_schema(::Any, key::AbstractString)
    return abstract_glm_card_schema(MixedModelCard, key)
end

const MIXED_MODEL_SPEC = CardSpec(
    mixed_model_card_schema,
    type = MixedModelCard,
    label = "Mixed Model"
)

function interp_card_schema(::Any, key::AbstractString)
    required = String["method", "input", "targets"]
    properties = StringDict(
        "type" => json_const(key),
        "method" => json_string(enum = keys(INTERPOLATION_METHODS)),
        "method_options" => json_object(),
        "input" => JSON_VARIABLE,
        "targets" => JSON_NONEMPTY_VARIABLES,
        "partition" => JSON_VARIABLE,
        "suffix" => json_string(minLength = 1)
    )
    allOf = conditional_options_schemas(INTERPOLATION_METHODS)
    return json_object(; properties, allOf, required)
end

const INTERP_SPEC = CardSpec(
    interp_card_schema,
    type = InterpCard,
    label = "Interpolation"
)

function gaussian_encoding_card_schema(::Any, key::AbstractString)
    required = String["input", "n_components"]
    properties = StringDict(
        "type" => json_const(key),
        "method" => json_string(enum = keys(TEMPORAL_PREPROCESSING_METHODS)),
        "method_options" => json_object(),
        "input" => JSON_VARIABLE,
        "n_components" => json_integer(minimum = 1),
        "lambda" => json_number(exclusiveMinimum = 0),
        "suffix" => json_string(minLength = 1)
    )
    allOf = conditional_options_schemas(TEMPORAL_PREPROCESSING_METHODS)
    return json_object(; properties, allOf, required)
end

const GAUSSIAN_ENCODING_SPEC = CardSpec(
    gaussian_encoding_card_schema,
    type = GaussianEncodingCard,
    label = "Gaussian Encoding"
)

function streamliner_card_schema(::Any, key::AbstractString)
    required = String["model", "training"]
    funnels = PARSER[].funnels
    default_funnel = ""
    funnel_property = json_string(enum = keys(funnels))
    funnel_property["default"] = default_funnel
    properties = StringDict(
        "type" => json_const(key),
        "funnel" => funnel_property,
        "partition" => JSON_VARIABLE,
        "suffix" => json_string(minLength = 1)
    )

    model_dir = isassigned(MODEL_DIR) ? MODEL_DIR[] : nothing
    training_dir = isassigned(TRAINING_DIR) ? TRAINING_DIR[] : nothing

    conditions = StringDict[]

    if isnothing(model_dir)
        properties["model"] = json_string()
        properties["model_metadata"] = json_object()
        push!(required, "model_metadata")
    else
        model_configs = available_streamliner_configs(model_dir)
        conditional_model_schemas = conditional_streamliner_schemas(
            model_dir, model_configs, "model"
        )
        append!(conditions, conditional_model_schemas)
        properties["model"] = json_string(enum = model_configs)
        properties["model_options"] = json_object()
    end

    if isnothing(training_dir)
        properties["training"] = json_string()
        properties["training_metadata"] = json_object()
        push!(required, "training_metadata")
    else
        training_configs = available_streamliner_configs(training_dir)
        conditional_training_schemas = conditional_streamliner_schemas(
            training_dir, training_configs, "training"
        )
        append!(conditions, conditional_training_schemas)
        properties["training"] = json_string(enum = training_configs)
        properties["training_options"] = json_object()
    end

    for (k, F) in pairs(funnels)
        schema = options_schema(F)
        merge!(schema["properties"], StringDict(keys(properties) .=> true))
        condition = match_property("funnel" => k, default_funnel)
        push!(conditions, conditional_schema(condition, schema))
    end

    return json_object(;
        properties, additionalProperties = true,
        allOf = conditions, required
    )
end

const STREAMLINER_SPEC = CardSpec(
    streamliner_card_schema,
    type = StreamlinerCard,
    label = "Streamliner"
)

function wild_card_schema(settings::Any, key::AbstractString)
    required = String["inputs"]

    properties = StringDict(
        "type" => json_const(key),
        "inputs" => JSON_VARIABLES,
        "suffix" => json_string(minLength = 1)
    )

    if settings.needs_order
        push!(required, "order_by")
        properties["order_by"] = JSON_NONEMPTY_VARIABLES
    else
        properties["order_by"] = JSON_VARIABLES
    end

    if settings.needs_targets
        push!(required, "targets")
        push!(required, "suffix")
        properties["targets"] = JSON_NONEMPTY_VARIABLES
        properties["outputs"] = json_array(items = json_string(minLength = 1))
    else
        push!(required, "outputs")
        properties["targets"] = JSON_VARIABLES
        properties["outputs"] = JSON_NONEMPTY_VARIABLES
    end

    if settings.allows_weights
        properties["weights"] = JSON_VARIABLE
    end

    if settings.allows_partition
        properties["partition"] = JSON_VARIABLE
    end

    return json_object(; properties, required)
end

function register_wild_card(key::Symbol; label::AbstractString, settings::WildCardSettings)
    type = WildCard{key}
    spec = CardSpec(wild_card_schema; type, label, settings)
    return register_card(string(key) => spec)
end
