"""
    struct WildCard <: Card
        train::T
        evaluate::E
        order_by::Vector{String}
        inputs::Vector{String}
        targets::Vector{String}
        weights::Union{String, Nothing}
        partition::Union{String, Nothing}
        outputs::Vector{String}
    end

Custom `card` that uses arbitrary training and evaluations functions.
"""
struct WildCard{T, E} <: StandardCard
    train::T
    evaluate::E
    order_by::Vector{String}
    inputs::Vector{String}
    targets::Vector{String}
    weights::Union{String, Nothing}
    partition::Union{String, Nothing}
    outputs::Vector{String}
end

## StandardCard interface

sorting_vars(wc::WildCard) = wc.order_by
grouping_vars(::WildCard) = String[]
input_vars(wc::WildCard) = wc.inputs
target_vars(::WildCard) = wc.targets
weight_var(wc::WildCard) = wc.weights
partition_var(wc::WildCard) = wc.partition
output_vars(wc::WildCard) = wc.outputs

_train(wc::WildCard, t, id; weights = nothing) = wc.train(wc, t, id; weights)

(wc::WildCard)(model, t, id) = wc.evaluate(wc, model, t, id)

## UI representation

function CardWidget(::Type{WildCard})

    fields = Widget[
        Widget("order_by"),
        Widget("inputs"),
        Widget("targets", required = false),
        Widget("weights", required = false),
        Widget("partition", required = false),
        Widget("outputs"),
    ]

    return CardWidget(;
        type = "wild",
        label = "Wild",
        output = OutputSpec("outputs"),
        fields
    )
end
