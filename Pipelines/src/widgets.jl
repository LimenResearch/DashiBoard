abstract type AbstractWidget end

@kwdef struct InputWidget <: AbstractWidget
    widget::String = "input"
    key::String
    label::String
    value::Any
    type::String = "text"
    attributes::Dict{String, Any} = Dict{String, Any}()
    conditional::Dict{String, Any} = Dict{String, Any}()
end

function SuffixWidget(; value::AbstractString, attributes::AbstractDict = Dict{String, Any}())
    return InputWidget(; key = "suffix", label = "Suffix", value = value, attributes)
end

@kwdef struct SelectWidget <: AbstractWidget
    widget::String = "select"
    key::String
    label::String
    value::Any
    type::String = "text"
    options::Any
    multiple::Bool
    attributes::Dict{String, Any} = Dict{String, Any}()
    conditional::Dict{String, Any} = Dict{String, Any}()
end

function MethodWidget(methods; attributes::AbstractDict = Dict{String, Any}())
    return SelectWidget(;
        key = "method",
        label = "Method",
        value = "",
        multiple = false,
        options = methods,
        attributes
    )
end

function OrderWidget(;
        attributes::AbstractDict = Dict{String, Any}(),
        conditional::AbstractDict = Dict{String, Any}()
    )
    return SelectWidget(;
        key = "order_by",
        label = "Order",
        value = [],
        multiple = true,
        options = Dict("-v" => "names"),
        attributes,
        conditional
    )
end

function GroupWidget(;
        attributes::AbstractDict = Dict{String, Any}(),
        conditional::AbstractDict = Dict{String, Any}()
    )
    return SelectWidget(;
        key = "by",
        label = "Group",
        value = [],
        multiple = true,
        options = Dict("-v" => "names"),
        attributes,
        conditional
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
