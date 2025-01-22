widget_config(key::AbstractString) = WIDGET_CONFIG[][key]

struct Widget
    widget::String
    key::String
    label::String
    placeholder::String
    value::Any
    min::Union{Float64, Nothing}
    max::Union{Float64, Nothing}
    step::Union{Float64, Nothing}
    options::Any
    multiple::Bool
    type::String
    visible::Union{Dict{String, Any}, Bool}
    required::Union{Dict{String, Any}, Bool}
end

function default_value(widget, type, multiple)
    multiple && return []
    widget === "input" && type === "text" && return ""
    return nothing
end

function Widget(
        key::AbstractString,
        conf::AbstractDict = widget_config(key);
        widget = conf["widget"],
        type = get(conf, "type", "text"),
        label = get(conf, "label", ""),
        placeholder = get(conf, "placeholder", ""),
        multiple = get(conf, "multiple", false),
        value = default_value(widget, type, multiple),
        min = get(conf, "min", nothing),
        max = get(conf, "max", nothing),
        step = get(conf, "step", nothing),
        options = get(conf, "options", nothing),
        visible = true,
        required = visible
    )

    (visible isa Bool) || (visible = Dict{String, Any}(visible))
    (required isa Bool) || (required = Dict{String, Any}(required))

    return Widget(
        widget,
        key,
        label,
        placeholder,
        value,
        min,
        max,
        step,
        options,
        multiple,
        type,
        visible,
        required,
    )
end

struct OutputSpec
    field::String
    suffixField::Union{String, Nothing}
end

OutputSpec(field::AbstractString) = OutputSpec(field, nothing)

@kwdef struct CardWidget
    label::String
    type::String
    output::OutputSpec
    fields::Vector{Widget}
end
