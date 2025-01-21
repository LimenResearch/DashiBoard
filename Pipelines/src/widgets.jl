abstract type AbstractWidget end

@kwdef struct NumberWidget <: AbstractWidget
    widget::String = "input"
    key::String
    label::String
    placeholder::String
    value::Float64 = NaN
    min::Union{Float64, Nothing} = nothing
    max::Union{Float64, Nothing} = nothing
    step::Union{Float64, Nothing} = nothing
    type::String = "number"
    conditional::Dict{String, Any} = Dict{String, Any}()
end

@kwdef struct TextWidget <: AbstractWidget
    widget::String = "input"
    key::String
    label::String
    placeholder::String
    value::String = ""
    type::String = "text"
    conditional::Dict{String, Any} = Dict{String, Any}()
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
    conditional::Dict{String, Any}
end

function SelectWidget(;
        key::AbstractString,
        label::AbstractString,
        placeholder::AbstractString,
        options::Any,
        multiple::Bool = false,
        value = multiple ? [] : nothing,
        type::AbstractString = "text",
        conditional::AbstractDict = Dict{String, Any}()
    )

    widget = "select"

    return SelectWidget(widget, key, label, placeholder, options, multiple, value, type, conditional)
end

function MethodWidget(; options, value = nothing)
    key = "method"
    label = "Method"
    placeholder = "Select method..."
    return SelectWidget(; key, label, placeholder, options, value)
end

function VariableWidget(;
        key::AbstractString, label::AbstractString, placeholder::AbstractString,
        multiple::Bool = false, conditional::AbstractDict = Dict{String, Any}()
    )
    options = Dict("-v" => "names")
    return SelectWidget(; key, label, placeholder, options, multiple, conditional)
end

function TargetWidget(;
        multiple::Bool,
        conditional::AbstractDict = Dict{String, Any}()
    )

    key = multiple ? "targets" : "target"
    label = multiple ? "Targets" : "Target"
    placeholder = multiple ? "Select target variables..." : "Select target variable..."
    return VariableWidget(; key, label, placeholder, multiple, conditional)
end

function PredictorWidget(;
        multiple::Bool,
        conditional::AbstractDict = Dict{String, Any}()
    )

    key = multiple ? "predictors" : "predictor"
    label = multiple ? "Predictors" : "Predictor"
    placeholder = multiple ? "Select predictor variables..." : "Select predictor variable..."
    return VariableWidget(; key, label, placeholder, multiple, conditional)
end

function WeightsWidget(; conditional::AbstractDict = Dict{String, Any}())
    key = "weights"
    label = "Weights"
    placeholder = "Select weight variable..."

    return VariableWidget(; key, label, placeholder, conditional)
end

function PartitionWidget(; conditional::AbstractDict = Dict{String, Any}())
    key = "partition"
    label = "Partition"
    placeholder = "Select partition variable..."
    return VariableWidget(; key, label, placeholder, conditional)
end

function OrderWidget(; conditional::AbstractDict = Dict{String, Any}())
    key = "order_by"
    label = "Order"
    placeholder = "Select ordering variables..."
    multiple = true
    return VariableWidget(; key, label, placeholder, multiple, conditional)
end

function GroupWidget(; conditional::AbstractDict = Dict{String, Any}())
    key = "by"
    label = "Group"
    placeholder = "Select grouping variables..."
    multiple = true
    return VariableWidget(; key, label, placeholder, multiple, conditional)
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
