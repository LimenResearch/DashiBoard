@kwarg struct WildCardSettings
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
    weights::Maybe{String} = nothing
    partition::Maybe{String} = nothing
    suffix::Maybe{String} = nothing
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

## IR

function WildCardIR(settings::Any)
    input_property = Property("inputs" => VARIABLES_DEF, required = true)
    order_by_property = if settings.needs_order
        Property("order_by" => NONEMPTY_VARIABLES_DEF, required = true)
    else
        Property("order_by" => VARIABLES_DEF, required = false)
    end

    output_array = ArrayIR{String}(items = StringIR(minLength = 1), minItems = 1)
    output_properties = if settings.needs_targets
        Property[
            Property("targets" => NONEMPTY_VARIABLES_DEF, required = true),
            Property("suffix" => StringIR(minLength = 1), required = true),
            Property("outputs" => output_array, required = false),
        ]
    else
        Property[
            Property("targets" => VARIABLES_DEF, required = false),
            Property("outputs" => output_array, required = true),
        ]
    end

    properties = Property[input_property, order_by_property]
    append!(properties, output_properties)

    if settings.allows_weights
        push!(properties, Property("weights" => VARIABLE_DEF, required = false))
    end

    if settings.allows_partition
        push!(properties, Property("partition" => VARIABLE_DEF, required = false))
    end

    return ObjectIR(; properties)
end
