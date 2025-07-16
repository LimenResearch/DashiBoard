"""
    struct WildCard{train, evaluate} <: Card
        order_by::Vector{String}
        inputs::Vector{String}
        targets::Vector{String}
        weights::Union{String, Nothing}
        partition::Union{String, Nothing}
        outputs::Vector{String}
    end

Custom `card` that uses arbitrary training and evaluations functions.
"""
struct WildCard{train, evaluate} <: StandardCard
    order_by::Vector{String}
    inputs::Vector{String}
    targets::Vector{String}
    weights::Union{String, Nothing}
    partition::Union{String, Nothing}
    outputs::Vector{String}
end

function WildCard{train, evaluate}(c::AbstractDict) where {train, evaluate}
    order_by::Vector{String} = get(c, "order_by", String[])
    inputs::Vector{String} = get(c, "inputs", String[])
    targets::Vector{String} = get(c, "targets", String[])
    outputs::Vector{String} = get(c, "outputs", String[])

    weights = get(c, "weights", nothing)
    partition = get(c, "partition", nothing)

    return WildCard{train, evaluate}(
        order_by,
        inputs,
        targets,
        weights,
        partition,
        outputs,
    )
end

function register_wild_card(name::AbstractString, train, evaluate)
    return register_card(name, WildCard{train, evaluate})
end

## StandardCard interface

sorting_vars(wc::WildCard) = wc.order_by
grouping_vars(::WildCard) = String[]
input_vars(wc::WildCard) = wc.inputs
target_vars(wc::WildCard) = wc.targets
weight_var(wc::WildCard) = wc.weights
partition_var(wc::WildCard) = wc.partition
output_vars(wc::WildCard) = wc.outputs

_train(wc::WildCard{train}, t, id; weights = nothing) where {train} = train(wc, t, id; weights)

(wc::WildCard{<:Any, evaluate})(model, t, id) where {evaluate} = evaluate(wc, model, t, id)

## UI representation

# TODO: test
function CardWidget(::Type{WildCard}; type, label)

    fields = Widget[
        Widget("order_by"),
        Widget("inputs"),
        Widget("targets", required = false),
        Widget("weights", required = false),
        Widget("partition", required = false),
        Widget("outputs"),
    ]

    return CardWidget(; type, label, output = OutputSpec("outputs"), fields)
end
