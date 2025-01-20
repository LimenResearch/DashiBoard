abstract type AbstractWidget end

@kwdef struct NumberWidget <: AbstractWidget
    widget::String = "input"
    key::String
    label::String
    value::Union{Float64, Nothing}
    placeholder::String
    min::Union{Float64, Nothing}
    max::Union{Float64, Nothing}
    step::Union{Float64, Nothing}
    type::String = "number"
    conditional::Dict{String, Any} = Dict{String, Any}()
end

@kwdef struct TextWidget <: AbstractWidget
    widget::String = "input"
    key::String
    label::String
    value::Union{String, Nothing}
    placeholder::String
    type::String = "text"
    conditional::Dict{String, Any} = Dict{String, Any}()
end

function SuffixWidget(; value::AbstractString)
    key = "suffix"
    label = "Suffix"
    placeholder = "Select suffix..."
    return TextWidget(; key, label, value, placeholder)
end

@kwdef struct SelectWidget <: AbstractWidget
    widget::String = "select"
    key::String
    label::String
    value::Any
    options::Any
    multiple::Bool
    placeholder::String
    type::String = "text"
    conditional::Dict{String, Any} = Dict{String, Any}()
end

function MethodWidget(options)
    key = "method"
    label = "Method"
    placeholder = "Select method..."
    value = nothing
    multiple = false
    return SelectWidget(; key, label, value, options, multiple, placeholder)
end

function VariableWidget(;
        key::AbstractString, label::AbstractString, multiple::Bool,
        placeholder::AbstractString, conditional::AbstractDict = Dict{String, Any}()
    )

    value = multiple ? String[] : nothing
    options = Dict("-v" => "names")
    return SelectWidget(; key, label, value, options, multiple, placeholder, conditional)
end

function TargetWidget(;
        multiple::Bool,
        conditional::AbstractDict = Dict{String, Any}()
    )

    key = multiple ? "targets" : "target"
    label = multiple ? "Targets" : "Target"
    placeholder = multiple ? "Select target variables..." : "Select target variable..."
    return VariableWidget(; key, label, multiple, placeholder, conditional)
end

function PredictorWidget(;
        multiple::Bool,
        conditional::AbstractDict = Dict{String, Any}()
    )

    key = multiple ? "predictors" : "predictor"
    label = multiple ? "Predictors" : "Predictor"
    placeholder = multiple ? "Select predictor variables..." : "Select predictor variable..."
    return VariableWidget(; key, label, multiple, placeholder, conditional)
end

function WeightsWidget(; conditional::AbstractDict = Dict{String, Any}())

    multiple = false
    key = "weights"
    label = "Weights"
    placeholder = "Select weight variable..."

    return VariableWidget(; key, label, multiple, placeholder, conditional)
end

function PartitionWidget(; conditional::AbstractDict = Dict{String, Any}())

    multiple = false
    key = "partition"
    label = "Partition"
    placeholder = "Select partition variable..."
    return VariableWidget(; key, label, multiple, placeholder, conditional)
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
