"""
    struct WildCard{T} <: Card
        type::String
        order_by::Vector{String}
        inputs::Vector{String}
        targets::Vector{String}
        weights::Union{String, Nothing}
        partition::Union{String, Nothing}
        outputs::Vector{String}
    end

Custom `card` that uses arbitrary training and evaluations functions.

Overload the following methods for your custom type or symbol `T`:
1. `Pipelines._train(wc::WildCard{T}, tbl, id_var)`
2. `(wc::WildCard{T})(model, tbl, id_var)` (return output table of `model` from input table `tbl` and primary key `id_var` -)
3. `WildCardConfig(::Type{WildCard{T})` (optional and experimental, return [`WildCardConfig`](@ref) for extra customizability)

`Pipelines._train(wc::WildCard{T}, tbl, id_var)` trains the card given input table `tbl` and primary key `id_var`  and return a trained `model`.
`(wc::WildCard{T})(model, tbl, id_var)` returns the output table of `model` from input table `tbl` and primary key `id_var`.
Note that the columns of the output table must be exactly the union of
- the primary key `id_var` and
- the variables in `wc.outputs`.

!!! note
    The current `WildCard` interface is not fully finalized and is to be considered experimental.
    At the moment, it is not possible for a wild card to have additional fields to set parameters,
    but that may be implemented in the future.

## Examples

```julia
Pipelines._train(wc::WildCard{:trivial}, t, id_var) = nothing # replace with actual trained model
# Below, `model` will be the output of the `_train` function
function (wc::WildCard{:trivial})(model, t, id_var)
    id = t[id_var]
    nrows = length(id)
    return Dict(id_var => id, (k => zeros(nrows) for k in wc.outputs)...)
end
card_config = CardConfig{WildCard{:trivial}}(
    key = "trivial",
    label = "Trivial",
    needs_targets = false,
    needs_order = false,
    allows_partition = false,
    allows_weights = false
)
Pipelines.register_card(card_config)
```
"""
@kwdef struct WildCard{T} <: StandardCard
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

function WildCard{T}(c::AbstractDict) where {T}
    type::String = c["type"]
    # TODO: allow a `group_by` field as well?
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

    return WildCard{T}(
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

## UI representation

"""
    @kwdef struct WildCardConfig
        needs_order::Bool = false
        needs_targets::Bool = false
        allows_weights::Bool = false
        allows_partition::Bool = true
    end

Define whether a given wild card requires sorting and / or target variables.
Define whether it accepts a weights variable and / or a partition variable.
"""
@kwdef struct WildCardConfig
    needs_order::Bool = false
    needs_targets::Bool = false
    allows_weights::Bool = false
    allows_partition::Bool = true
end

WildCardConfig(::Type{<:WildCard}) = WildCardConfig()

function CardWidget(
        ::Type{WildCard{T}}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    ) where {T}

    c = combine_options(StringDict(); global_options, user_options)

    config = WildCardConfig(WildCard{T})
    conditional_fields = Tuple{Widget, Bool}[
        (Widget("order_by", c), config.needs_order),
        (Widget("inputs", c), true),
        (Widget("targets", c), config.needs_targets),
        (Widget("weights", c), config.allows_weights),
        (Widget("partition", c), config.allows_partition),
        (Widget("output", c), !config.needs_targets),
        (Widget("suffix", c), config.needs_targets),
    ]

    fields = map(first, filter(last, conditional_fields))
    output = config.needs_targets ? OutputSpec("targets", "suffix") : OutputSpec("output")
    return CardWidget(key, fields, output)
end
