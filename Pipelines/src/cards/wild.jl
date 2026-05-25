"""
    struct WildCard{train, evaluate} <: Card
        type::String
        order_by::Vector{String}
        inputs::Vector{String}
        targets::Vector{String}
        weights::Union{String, Nothing}
        partition::Union{String, Nothing}
        outputs::Vector{String}
    end

Custom `card` that uses arbitrary training and evaluations functions.
"""
@kwdef struct WildCard{train, evaluate} <: StandardCard
    type::String
    order_by::Vector{String}
    inputs::Vector{String}
    targets::Vector{String}
    weights::Union{String, Nothing}
    partition::Union{String, Nothing}
    outputs::Vector{String}
end

function get_metadata(wc::WildCard)
    return StringDict(
        "type" => wc.type,
        "order_by" => wc.order_by,
        "inputs" => wc.inputs,
        "weights" => wc.weights,
        "partition" => wc.partition,
        "targets" => wc.targets,
        "outputs" => wc.outputs
    )
end

function WildCard{train, evaluate}(c::AbstractDict) where {train, evaluate}
    type::String = c["type"]
    order_by::Vector{String} = get(c, "order_by", String[])
    inputs::Vector{String} = c["inputs"]
    targets::Vector{String} = get(c, "targets", String[])

    outputs::Vector{String} = get(c, "outputs") do
        suffix::Union{String, Nothing} = get(c, "suffix", nothing)
        if isnothing(suffix)
            output::String = c["output"]
            [output]
        else
            join_names(targets, suffix)
        end
    end

    weights = get(c, "weights", nothing)
    partition = get(c, "partition", nothing)

    return WildCard{train, evaluate}(
        type,
        order_by,
        inputs,
        targets,
        weights,
        partition,
        outputs,
    )
end

## StandardCard interface

function SourceVariables(wc::WildCard)
    return SourceVariables(;
        wc.order_by,
        wc.inputs,
        wc.targets,
        wc.weights,
        wc.partition
    )
end

OutputVariables(wc::WildCard) = OutputVariables(wc.outputs)

_train(wc::WildCard{train}, t, id_var::AbstractPrimaryKey) where {train} = train(wc, t, id_var)

(wc::WildCard{<:Any, evaluate})(model, t, id_var::AbstractPrimaryKey) where {evaluate} = evaluate(wc, model, t, id_var)

## UI representation

# function CardWidget(::WildCardtrain, config::CardUI, evaluate}}, c::AbstractDict) where {train, evaluate}
#     conditional_fields = Tuple{Widget, Bool}[
#         (Widget("order_by", c), config.needs_order),
#         (Widget("inputs", c), true),
#         (Widget("targets", c), config.needs_targets),
#         (Widget("weights", c), config.allows_weights),
#         (Widget("partition", c), config.allows_partition),
#         (Widget("output", c), !config.needs_targets),
#         (Widget("suffix", c), config.needs_targets),
#     ]

#     fields = map(first, filter(last, conditional_fields))
#     output = config.needs_targets ? OutputSpec("targets", "suffix") : OutputSpec("output")
#     return CardWidget(config.key, config.label, fields, output)
# end
