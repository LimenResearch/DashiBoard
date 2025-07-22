const WIDGET_CONFIGS = ScopedValue{StringDict}(parse_toml_config("widget_configs"))

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
    visible::Union{StringDict, Bool}
    required::Union{StringDict, Bool}
end

function default_value(widget, type, multiple)
    multiple && return []
    widget === "input" && type === "text" && return ""
    return nothing
end

function Widget(key::AbstractString, widget_configs::AbstractDict = WIDGET_CONFIGS[]; options...)
    return Widget(widget_configs[key]; key, options...)
end

function Widget(key::AbstractString, widget_configs::AbstractDict, conf::AbstractDict; options...)
    return Widget(merge(widget_configs[key], conf); key, options...)
end

function Widget(
        conf::AbstractDict;
        widget = conf["widget"],
        key = conf["key"],
        type = get(conf, "type", "text"),
        label = get(conf, "label", ""),
        placeholder = get(conf, "placeholder", ""),
        multiple = get(conf, "multiple", false),
        value = get(conf, "value", default_value(widget, type, multiple)),
        min = get(conf, "min", nothing),
        max = get(conf, "max", nothing),
        step = get(conf, "step", nothing),
        options = get(conf, "options", nothing),
        visible = get(conf, "visible", true),
        required = get(conf, "required", visible)
    )

    (visible isa Bool) || (visible = StringDict(visible))
    (required isa Bool) || (required = StringDict(required))

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

function generate_widget(
        conf::AbstractDict,
        type::AbstractString,
        name::AbstractString,
        idx::Integer
    )

    key = string(type, "_", "options", ".", idx, ".", conf["key"])
    visible = Dict(type => [name])
    return Widget(conf; key, visible)
end

struct OutputSpec
    field::String
    suffixField::Union{String, Nothing}
    numberField::Union{String, Nothing}
end

function OutputSpec(field::AbstractString, suffixfield::Union{AbstractString, Nothing} = nothing)
    return OutputSpec(field, suffixfield, nothing)
end

struct CardWidget
    type::String
    label::String
    fields::Vector{Widget}
    output::OutputSpec
end
