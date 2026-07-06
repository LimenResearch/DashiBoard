function json_schema(
        key::AbstractString, variables::AbstractVector;
        additional_properties::Bool = false
    )

    schema = json_schema(key; additional_properties)

    # TODO: update variables with dict options
    variable_schema = json_enum(variables)
    variables_schema = Dict(
        "type" => "array",
        "items" => variable_schema,
        "default" => String[]
    )
    nonempty_variables_schema = Dict(
        "type" => "array",
        "items" => variable_schema,
        "minItems" => 1
    )

    schema["\$defs"] = Dict(
        "variable" => variable_schema,
        "variables" => variables_schema,
        "nonempty_variables" => nonempty_variables_schema,
    )
    return schema
end

function json_schema(key::AbstractString; additional_properties::Bool = false)::StringDict
    spec = get_spec(key)
    schema = spec.schema(spec.settings, key)
    schema["title"] = spec.label
    schema["additionalProperties"] = additional_properties
    return schema
end

function split_card_schema(::Any, key::AbstractString)
    properties = Dict(
        "type" => Dict("const" => key),
        "order_by" => JSON_NONEMPTY_VARIABLES,
        "group_by" => JSON_VARIABLES,
        "method" => json_enum(keys(SPLITTING_METHODS)),
        "method_options" => Dict("type" => "object"),
        "output" => json_string(min = 1),
    )
    return StringDict(
        "type" => "object",
        "properties" => properties,
        "allOf" => conditional_options_schemas(SPLITTING_METHODS),
        "required" => ["type", "order_by", "method", "output"]
    )
end

const SPLIT_SPEC = CardSpec(split_card_schema, type = SplitCard, label = "Split")

function window_function_card_schema(::Any, key::AbstractString)
    properties = Dict(
        "type" => Dict("const" => key),
        "order_by" => JSON_NONEMPTY_VARIABLES,
        "group_by" => JSON_VARIABLES,
        "method" => json_enum(keys(WINDOW_FUNCTIONS)),
        "output" => json_string(min = 1),
    )
    return StringDict(
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

function rescale_card_schema(::Any, key::AbstractString)
    properties = Dict(
        "type" => Dict("const" => key),
        "method" => json_enum(keys(RESCALERS)),
        "group_by" => JSON_VARIABLES,
        "inputs" => JSON_VARIABLES,
        "targets" => JSON_VARIABLES,
        "partition" => JSON_VARIABLE,
        "suffix" => json_string(min = 1),
        "target_suffix" => json_string(min = 1)
    )
    return StringDict(
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

function cluster_card_schema(::Any, key::AbstractString)
    properties = Dict(
        "type" => Dict("const" => key),
        "method" => json_enum(keys(CLUSTERING_METHODS)),
        "method_options" => Dict("type" => "object"),
        "inputs" => JSON_NONEMPTY_VARIABLES,
        "weights" => JSON_VARIABLE,
        "partition" => JSON_VARIABLE,
        "output" => json_string(min = 1)
    )
    return StringDict(
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

function dimensionality_reduction_card_schema(::Any, key::AbstractString)
    properties = Dict(
        "type" => Dict("const" => key),
        "method" => json_enum(keys(PROJECTION_METHODS)),
        "method_options" => Dict("type" => "object"),
        "inputs" => JSON_NONEMPTY_VARIABLES,
        "partition" => JSON_VARIABLE,
        "n_components" => json_integer(min = 1),
        "output" => json_string(min = 1)
    )
    return StringDict(
        "type" => "object",
        "properties" => properties,
        "allOf" => conditional_options_schemas(PROJECTION_METHODS),
        "required" => ["type", "method", "inputs", "n_components"]
    )
end

const DIMENSIONALITY_REDUCTION_SPEC = CardSpec(
    dimensionality_reduction_card_schema,
    type = DimensionalityReductionCard,
    label = "Dimensionality Reduction"
)

function abstract_glm_card_schema(
        ::Type{C}, key::AbstractString
    ) where {C <: AbstractGLMCard}
    required = String["type", "target"]
    properties = Dict{String, Any}(
        "type" => Dict("const" => key),
        "distribution" => json_enum(keys(NOISE_MODELS)),
        "link" => json_enum(keys(LINK_TYPES)),
        "weights" => JSON_VARIABLE,
        "partition" => JSON_VARIABLE,
        "target" => JSON_VARIABLE,
        "suffix" => json_string(min = 1)
    )
    if has_grouping_factor(C)
        properties["fixed_effect_terms"] = Dict("type" => "array")
        properties["random_effect_terms"] = Dict("type" => "array")
        properties["grouping_factor"] = JSON_VARIABLE
        append!(required, ["fixed_effect_terms", "random_effect_terms", "grouping_factor"])
    else
        properties["inputs"] = Dict("type" => "array")
        append!(required, ["inputs"])
    end

    return StringDict(
        "type" => "object",
        "properties" => properties,
        "required" => required
    )
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
    required = String["type", "method", "input", "targets"]
    properties = Dict(
        "type" => Dict("const" => key),
        "method" => json_enum(keys(INTERPOLATION_METHODS)),
        "method_options" => Dict("type" => "object"),
        "input" => JSON_VARIABLE,
        "targets" => JSON_NONEMPTY_VARIABLES,
        "partition" => JSON_VARIABLE,
        "suffix" => json_string(min = 1)
    )

    return StringDict(
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

function gaussian_encoding_card_schema(::Any, key::AbstractString)
    required = String["type", "input", "n_components"]
    properties = Dict(
        "type" => Dict("const" => key),
        "method" => json_enum(keys(TEMPORAL_PREPROCESSING_METHODS)),
        "method_options" => Dict("type" => "object"),
        "input" => JSON_VARIABLE,
        "n_components" => json_integer(min = 1),
        "lambda" => json_number(exclusive_min = 0),
        "suffix" => json_string(min = 1)
    )

    return StringDict(
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

function streamliner_card_schema(::Any, key::AbstractString)
    required = String["type", "model", "training"]
    funnels = PARSER[].funnels
    default_funnel = ""
    properties = StringDict(
        "type" => Dict("const" => key),
        "funnel" => merge(json_enum(keys(funnels)), Dict("default" => default_funnel)),
        "partition" => JSON_VARIABLE,
        "suffix" => json_string(min = 1)
    )

    model_dir = isassigned(MODEL_DIR) ? MODEL_DIR[] : nothing
    training_dir = isassigned(TRAINING_DIR) ? TRAINING_DIR[] : nothing

    conditions = StringDict[]

    if isnothing(model_dir)
        properties["model"] = Dict("type" => "string")
        properties["model_metadata"] = Dict("type" => "object")
        push!(required, "model_metadata")
    else
        model_configs = available_streamliner_configs(model_dir)
        conditional_model_schemas = conditional_streamliner_schemas(
            model_dir, model_configs, "model"
        )
        append!(conditions, conditional_model_schemas)
        properties["model"] = json_enum(model_configs)
        properties["model_options"] = Dict("type" => "object")
    end

    if isnothing(training_dir)
        properties["training"] = Dict("type" => "string")
        properties["training_metadata"] = Dict("type" => "object")
        push!(required, "training_metadata")
    else
        training_configs = available_streamliner_configs(training_dir)
        conditional_training_schemas = conditional_streamliner_schemas(
            training_dir, training_configs, "training"
        )
        append!(conditions, conditional_training_schemas)
        properties["training"] = json_enum(training_configs)
        properties["training_options"] = Dict("type" => "object")
    end

    for (k, F) in pairs(funnels)
        schema = options_schema(F; additional_properties = true)
        for p in keys(schema["properties"])
            properties[p] = Dict() # allow these properties to exist in global schema
        end
        condition = StringDict("properties" => Dict("funnel" => Dict("const" => k)))
        if k == default_funnel
            condition = StringDict(
                "anyOf" => [condition, Dict("not" => Dict("required" => ["funnel"]))]
            )
        end
        push!(conditions, conditional_schema(condition, schema))
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

function wild_card_schema(settings::Any, key::AbstractString)
    required = String["type", "inputs"]

    properties = Dict{String, Any}(
        "type" => Dict("const" => key),
        "inputs" => JSON_VARIABLES,
        "suffix" => json_string(min = 1)
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
        properties["outputs"] = Dict("type" => "array", "items" => json_string(min = 1))
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

    return StringDict(
        "type" => "object",
        "properties" => properties,
        "required" => required
    )
end

function register_wild_card(key::Symbol; label::AbstractString, settings::WildCardSettings)
    type = WildCard{key}
    spec = CardSpec(wild_card_schema; type, label, settings)
    return register_card(string(key) => spec)
end
