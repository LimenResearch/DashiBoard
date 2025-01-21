widget_config() = TOML.parsefile(joinpath(@__DIR__, "..", "assets", "widgets.toml"))

abstract type AbstractWidget end

@kwdef struct NumberWidget <: AbstractWidget
    widget::String = "input"
    key::String
    label::String
    placeholder::String
    value::Union{Float64, Nothing} = nothing
    min::Union{Float64, Nothing} = nothing
    max::Union{Float64, Nothing} = nothing
    step::Union{Float64, Nothing} = nothing
    type::String = "number"
    visible::Dict{String, Any} = Dict{String, Any}()
    required::Dict{String, Any} = Dict{String, Any}()
end

@kwdef struct TextWidget <: AbstractWidget
    widget::String = "input"
    key::String
    label::String
    placeholder::String
    value::String = ""
    type::String = "text"
    visible::Dict{String, Any} = Dict{String, Any}()
    required::Dict{String, Any} = Dict{String, Any}()
end

function SuffixWidget(; value::AbstractString)
    key = "suffix"
    label = "Suffix"
    placeholder = "Select suffix..."
    return TextWidget(; key, label, placeholder, value)
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
