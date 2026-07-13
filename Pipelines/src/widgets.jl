## Widget description

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

function Widget(
        config::AbstractDict;
        widget = config["widget"],
        key = config["key"],
        type = get(config, "type", "text"),
        label = get(config, "label", ""),
        placeholder = get(config, "placeholder", ""),
        multiple = get(config, "multiple", false),
        value = get(config, "value", default_value(widget, type, multiple)),
        min = get(config, "min", nothing),
        max = get(config, "max", nothing),
        step = get(config, "step", nothing),
        options = get(config, "options", nothing),
        visible = get(config, "visible", true),
        required = get(config, "required", visible)
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

Widget(key::AbstractString, d::AbstractDict; options...) = Widget(d[key]; key, options...)

function method_dependent_widgets(settings::AbstractDict, key::AbstractString, methods::AbstractDict)
    option_key = string(key, "_", "options")
    wdgs = Widget[]
    for (m, config) in pairs(methods)
        for wdg in config["widgets"]
            wdg_key = wdg["key"]
            c = merge(get(settings, wdg_key, StringDict()), wdg)
            c["key"] = join([option_key, m, wdg_key], ".")
            c["visible"] = Dict(key => [m])
            push!(wdgs, Widget(c))
        end
    end
    if !allunique(w -> w.key, wdgs)
        # TODO: better error message, or maybe disallow dots in keys
        throw(ArgumentError("Ambiguous widget configuration"))
    end
    return wdgs
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

function CardWidget(type::AbstractString, fields::AbstractVector, output::OutputSpec)
    return CardWidget(type, get_label(get_spec(type)), fields, output)
end

## Widget configurations

# Configuration used to describe custom widgets to use for a given card type.
@kwdef struct CardWidgetConfigs
    widget_configs::StringDict = StringDict()
    methods::StringDict = StringDict()
end

function CardWidgetConfigs(d::AbstractDict)
    widget_configs::StringDict = d["widget_configs"]
    methods::StringDict = get(d, "methods", StringDict())
    return CardWidgetConfigs(; widget_configs, methods)
end

function card_widgets(options::AbstractDict = StringDict())
    widgets = CardWidget[]
    global_options = parse_toml_config("widget_configs")
    for (k, spec) in pairs(CARD_SPECS)
        user_options = get(options, k, StringDict())
        push!(widgets, CardWidget(spec.type, k; global_options, user_options))
    end
    return widgets
end

function combine_options(card_options; global_options, user_options)
    return mergewith(
        merge,
        global_options,
        card_options,
        user_options
    )
end
