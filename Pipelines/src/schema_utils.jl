struct DashiStyle <: StructUtils.StructStyle end

StructUtils.lower(::DashiStyle, x::Symbol) = string(x)

StructUtils.lower(::DashiStyle, x::Enum) = string(Symbol(x))

function get_dashi(nt::NamedTuple, sym::Symbol)
    s = get(nt, sym, nothing)
    return isnothing(s) ? nothing : get(s, :dashi, nothing)
end

function enum_instances(::Type{T}) where {T}
    return [StructUtils.lower(DashiStyle(), x) for x in instances(T)]
end

function schema_from_tags(T::Type, config::Union{AbstractDict, Nothing}, default)
    schema = StringDict()

    if T <: Union{Integer, Nothing}
        schema["type"] = "integer"
    elseif T <: Union{Number, Nothing}
        schema["type"] = "number"
    elseif T <: Union{AbstractString, Symbol, Nothing}
        schema["type"] = "string"
    elseif T <: Union{AbstractVector, Nothing}
        schema["type"] = "array"
    elseif T <: Union{Enum, Nothing}
        schema["type"] = "string"
        schema["enum"] = enum_instances(T)
    else
        throw(ArgumentError("Type $T not supported in json schema generation."))
    end

    if !isnothing(default)
        schema["default"] = StructUtils.lower(DashiStyle(), default)
    end

    if !isnothing(config)
        merge!(schema, config)
    end

    return (Nothing <: T) ? (nullable(schema), false) : (schema, isnothing(default))
end

function options_schema(::Type{T}) where {T}
    properties = StringDict()
    required = String[]
    tags = fieldtags(DashiStyle(), T)
    defaults = fielddefaults(DashiStyle(), T)

    for k in fieldnames(T)
        sk = string(k)
        config = get_dashi(tags, k)
        default = get(defaults, k, nothing)
        sch, is_req = schema_from_tags(fieldtype(T, k), config, default)
        properties[sk] = sch
        is_req && push!(required, sk)
    end
    return Dict(
        "type" => "object",
        "properties" => properties,
        "required" => required
    )
end

function conditional_options_schema(::Type{T}, k::AbstractString) where {T}
    method_options = options_schema(T)
    is_required = !isempty(method_options["required"])
    return Dict(
        "if" => Dict("properties" => Dict("method" => Dict("const" => k))),
        "then" => Dict(
            "properties" => Dict("method_options" => method_options),
            "required" => is_required ? String["method_options"] : String[]
        )
    )
end

function conditional_options_schemas(d)
    return [conditional_options_schema(v, k) for (k, v) in pairs(d)]
end

# JSON schema utils

json_integer(; kwargs...) = json_number("integer"; kwargs...)

function json_number(
        type::AbstractString = "number";
        min::Union{Integer, Nothing} = nothing,
        max::Union{Integer, Nothing} = nothing,
        exclusive_min::Union{Integer, Nothing} = nothing,
        exclusive_max::Union{Integer, Nothing} = nothing,
    )
    sch = Dict{String, Any}("type" => type)
    isnothing(min) || (sch["minimum"] = min)
    isnothing(max) || (sch["maximum"] = max)
    isnothing(exclusive_min) || (sch["exclusiveMinimum"] = exclusive_min)
    isnothing(exclusive_max) || (sch["exclusiveMaximum"] = exclusive_max)
    return sch
end

function json_string(; min::Integer = 0)
    return Dict("type" => "string", "minLength" => min)
end

json_enum(options) = json_enum("string", options)

function json_enum(type::AbstractString, options)
    _options = options isa AbstractVector ? options : collect(options)
    return Dict("type" => type, "enum" => options)
end

# TODO: update with dict options
json_var(vars) = json_enum(vars)

function json_vars(vars; min::Integer = 0)
    return Dict(
        "type" => "array",
        "items" => json_var(vars),
        "minItems" => min
    )
end

nullable(s) = StringDict("anyOf" => [s, Dict("type" => "null")])
