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

Widget(key::AbstractString, c::AbstractDict; options...) = Widget(c[key]; key, options...)

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

function extract_options(c::AbstractDict, key::AbstractString, m::AbstractString)
    option_key = string(key, "_", "options")
    r = r"^" * join([option_key, m, ""], ".") * r"(?<name>.*)$"
    return get(c, option_key) do
        d = StringDict()
        for (k, v) in pairs(c)
            m = match(r, k)
            isnothing(m) || (d[m[:name]] = v)
        end
        return d
    end
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
