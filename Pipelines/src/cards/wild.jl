"""
    struct WildCard{train, evaluate} <: Card
        type::String
        label::String
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
    label::String
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
        "label" => wc.label,
        "order_by" => wc.order_by,
        "inputs" => wc.inputs,
        "weights" => wc.weights,
        "partition" => wc.partition,
        "outputs" => wc.outputs
    )
end

function WildCard{train, evaluate}(c::AbstractDict) where {train, evaluate}
    type::String = c["type"]
    config = CARD_CONFIGS[type]
    label::String = card_label(c, config)

    order_by::Vector{String} = config.needs_order ? c["order_by"] : String[]
    inputs::Vector{String} = c["inputs"]
    targets::Vector{String} = config.needs_targets ? c["targets"] : String[]

    outputs::Vector{String} = if config.needs_targets
        suffix::String = c["suffix"]
        join_names(targets, suffix)
    else
        output::String = c["output"]
        [output]
    end

    weights = get(c, "weights", nothing)
    partition = get(c, "partition", nothing)

    return WildCard{train, evaluate}(
        type,
        label,
        order_by,
        inputs,
        targets,
        weights,
        partition,
        outputs,
    )
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

function CardWidget(config::CardConfig{WildCard{train, evaluate}}, ::AbstractDict) where {train, evaluate}
    conditional_fields = Tuple{Widget, Bool}[
        (Widget("order_by"), config.needs_order),
        (Widget("inputs"), true),
        (Widget("targets"), config.needs_targets),
        (Widget("weights"), config.allows_weights),
        (Widget("partition"), config.allows_partition),
        (Widget("output"), !config.needs_targets),
        (Widget("suffix"), config.needs_targets),
    ]

    fields = map(first, filter(last, conditional_fields))
    output = config.needs_targets ? OutputSpec("targets", "suffix") : OutputSpec("output")
    return CardWidget(config.key, config.label, fields, output)
end
