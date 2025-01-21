widget_config() = TOML.parsefile(joinpath(@__DIR__, "..", "assets", "widgets.toml"))

abstract type AbstractWidget end

struct NumberWidget <: AbstractWidget
    widget::String
    key::String
    label::String
    placeholder::String
    value::Union{Float64, Nothing}
    min::Union{Float64, Nothing}
    max::Union{Float64, Nothing}
    step::Union{Float64, Nothing}
    type::String
    visible::Dict{String, Any}
    required::Dict{String, Any}
end

function NumberWidget(
        key::AbstractString;
        value::Union{Real, Nothing} = nothing,
        min::Union{Real, Nothing} = nothing,
        max::Union{Real, Nothing} = nothing,
        step::Union{Real, Nothing} = nothing,
        visible::AbstractDict = Dict{String, Any}(),
        required::AbstractDict = visible
    )

    widget = "input"
    conf = widget_config()[key]
    label = get(conf, "label", "")
    placeholder = get(conf, "placeholder", "")
    type = "number"

    return NumberWidget(
        widget, key, label, placeholder, value, min, max, step, type, visible, required
    )
end

struct TextWidget <: AbstractWidget
    widget::String
    key::String
    label::String
    placeholder::String
    value::String
    type::String
    visible::Dict{String, Any}
    required::Dict{String, Any}
end

function TextWidget(
        key::AbstractString;
        value::AbstractString = "",
        visible::AbstractDict = Dict{String, Any}(),
        required::AbstractDict = visible
    )

    widget = "input"
    conf = widget_config()[key]
    label = get(conf, "label", "")
    placeholder = get(conf, "placeholder", "")
    type = "text"

    return TextWidget(widget, key, label, placeholder, value, type, visible, required)
end

struct SelectWidget <: AbstractWidget
    widget::String
    key::String
    label::String
    placeholder::String
    options::Any
    multiple::Bool
    value::Any
    type::String
    visible::Dict{String, Any}
    required::Dict{String, Any}
end

function SelectWidget(
        key::AbstractString;
        options = nothing, value = nothing,
        visible::AbstractDict = Dict{String, Any}(),
        required::AbstractDict = visible
    )

    widget = "select"
    conf = widget_config()[key]
    label = get(conf, "label", "")
    placeholder = get(conf, "placeholder", "")
    options = @something options conf["options"]
    multiple = get(conf, "multiple", false)
    type = get(conf, "type", "text")

    return SelectWidget(
        widget, key, label, placeholder, options, multiple,
        value, type, visible, required
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
    fields::Vector{AbstractWidget}
end
