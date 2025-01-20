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

function VariableWidget(;
        label::AbstractString, key::AbstractString, multiple::Bool,
        attributes::AbstractDict = Dict{String, Any}(),
        conditional::AbstractDict = Dict{String, Any}()
    )

    return SelectWidget(;
        key,
        label,
        value = multiple ? [] : nothing,
        multiple,
        options = Dict("-v" => "names"),
        attributes,
        conditional
    )
end

function TargetWidget(;
        multiple::Bool,
        attributes::AbstractDict = Dict{String, Any}(),
        conditional::AbstractDict = Dict{String, Any}()
    )

    key = multiple ? "targets" : "target"
    label = multiple ? "Targets" : "Target"
    return VariableWidget(; key, label, multiple, attributes, conditional)
end

function PredictorWidget(;
        multiple::Bool,
        attributes::AbstractDict = Dict{String, Any}(),
        conditional::AbstractDict = Dict{String, Any}()
    )

    key = multiple ? "predictors" : "predictor"
    label = multiple ? "Predictors" : "Predictor"
    return VariableWidget(; key, label, multiple, attributes, conditional)
end

function WeightsWidget(;
        attributes::AbstractDict = Dict{String, Any}(),
        conditional::AbstractDict = Dict{String, Any}()
    )

    multiple = false
    key = "weights"
    label = "Weights"
    return VariableWidget(; key, label, multiple, attributes, conditional)
end

function PartitionWidget(;
        attributes::AbstractDict = Dict{String, Any}(),
        conditional::AbstractDict = Dict{String, Any}()
    )

    multiple = false
    key = "partition"
    label = "Partition"
    return VariableWidget(; key, label, multiple, attributes, conditional)
end

function OrderWidget(;
        attributes::AbstractDict = Dict{String, Any}(),
        conditional::AbstractDict = Dict{String, Any}()
    )
    return VariableWidget(;
        key = "order_by",
        label = "Order",
        multiple = true,
        attributes,
        conditional
    )
end

function GroupWidget(;
        attributes::AbstractDict = Dict{String, Any}(),
        conditional::AbstractDict = Dict{String, Any}()
    )
    return VariableWidget(;
        key = "by",
        label = "Group",
        multiple = true,
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
