@kwdef struct WildCardSettings
    needs_order::Bool
    needs_targets::Bool
    allows_weights::Bool
    allows_partition::Bool
end

"""
    struct WildCard{T} <: Card
        order_by::Vector{String}
        inputs::Vector{String}
        targets::Vector{String}
        weights::Union{String, Nothing}
        partition::Union{String, Nothing}
        suffix::Union{String, Nothing}
        outputs::Vector{String}
    end

Custom `card` that uses arbitrary training and evaluations functions.

Overload the following methods for your custom type or symbol `T`:
1. `Pipelines._train(wc::WildCard{T}, tbl, id_var)`
2. `(wc::WildCard{T})(model, tbl, id_var)` (return output table of `model` from input table `tbl` and primary key `id_var` -)

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
settings = Pipelines.WildCardSettings(
    needs_order = false,
    needs_targets = false,
    allows_partition = false,
    allows_weights = false
)
Pipelines.register_wild_card(:trivial, "Trivial"; settings)
```
"""
@kwarg struct WildCard{T} <: StandardCard
    order_by::Vector{String} = String[]
    inputs::Vector{String}
    targets::Vector{String} = String[]
    weights::Union{String, Nothing} = nothing
    partition::Union{String, Nothing} = nothing
    suffix::Union{String, Nothing} = nothing
    outputs::Vector{String} = join_names(targets, suffix)
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

## Card registration

function register_wild_card(key::Symbol, label::AbstractString; settings::WildCardSettings)
    type = WildCard{key}
    spec = CardSpec(type, label; settings)
    return register_card(string(key) => spec)
end

## Card schema

function wild_card_schema(settings::Any)
    required = String["inputs"]

    properties = StringDict(
        "inputs" => JSON_VARIABLES,
        "suffix" => json_string(minLength = 1)
    )

    if settings.needs_order
        push!(required, "order_by")
        properties["order_by"] = JSON_NONEMPTY_VARIABLES
    else
        properties["order_by"] = JSON_VARIABLES
    end

    if settings.needs_targets
        push!(required, "targets")
        push!(required, "suffix")
        properties["targets"] = JSON_NONEMPTY_VARIABLES
        properties["outputs"] = json_array(items = json_string(minLength = 1))
    else
        push!(required, "outputs")
        properties["targets"] = JSON_VARIABLES
        properties["outputs"] = JSON_NONEMPTY_VARIABLES
    end

    if settings.allows_weights
        properties["weights"] = JSON_VARIABLE
    end

    if settings.allows_partition
        properties["partition"] = JSON_VARIABLE
    end

    return json_object(; properties, required)
end

## UI representation

function CardWidget(
        ::Type{WildCard{T}}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    ) where {T}

    c = combine_options(StringDict(); global_options, user_options)

    spec = get_spec(key)
    settings = spec.settings
    conditional_fields = Tuple{Widget, Bool}[
        (Widget("order_by", c), settings.needs_order),
        (Widget("inputs", c), true),
        (Widget("targets", c), settings.needs_targets),
        (Widget("weights", c), settings.allows_weights),
        (Widget("partition", c), settings.allows_partition),
        (Widget("outputs", c), !settings.needs_targets),
        (Widget("suffix", c), settings.needs_targets),
    ]

    fields = map(first, filter(last, conditional_fields))
    output = settings.needs_targets ? OutputSpec("targets", "suffix") : OutputSpec("outputs")
    return CardWidget(key, get_label(spec), fields, output)
end
