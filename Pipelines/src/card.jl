## Card state type

@kwdef struct CardState
    content::Union{Vector{UInt8}, Nothing} = nothing
    metadata::StringDict = StringDict()
end

function jldserialize(m)
    return mktemp() do path, io
        jldopen(path, "w") do file
            file["model_state"] = m
        end
        return read(io)
    end
end

function jlddeserialize(v::AbstractVector{UInt8}, k = "model_state")
    return mktemp() do path, io
        write(io, v)
        flush(io)
        jldopen(path) do file
            return file[k]
        end
    end
end

## Card interface

"""
    abstract type Card end

Abstract supertype to encompass all possible cards.

Current implementations:

- [`SplitCard`](@ref) (`type = "split"`),
- [`RescaleCard`](@ref) (`type = "rescale"`),
- [`ClusterCard`](@ref) (`type = "cluster"`),
- [`DimensionalityReductionCard`](@ref) (`type = "dimensionality_reduction"`),
- [`GLMCard`](@ref) (`type = "glm"`),
- [`MixedModelCard`](@ref) (`type = "mixed_model"`),
- [`InterpCard`](@ref) (`type = "interp"`),
- [`GaussianEncodingCard`](@ref) (`type = "gaussian_encoding"`),
- [`StreamlinerCard`](@ref) (`type = "streamliner"`),
- [`WildCard`](@ref).
"""
abstract type Card end

abstract type StandardCard <: Card end
abstract type SQLCard <: Card end
abstract type StreamingCard <: Card end

"""
    Card(d::AbstractDict)

Generate a [`Card`](@ref) based on a configuration dictionary `d`.

## Examples

Dictionaries are given in TOML format for clarity.

Card configuration `d`:

```toml
type = "cluster"
method = "kmeans"
method_options = {classes = 3}
inputs = [
    "wind_10m",
    "wind_20m",
    "temperature_10m",
    "temperature_20m",
    "precipitation",
    "irradiance",
    "humidity"
]
```

Resulting card:

```julia-repl
julia> card = Card(d);

julia> typeof(card)
ClusterCard

julia> card.clusterer
Pipelines.KMeansMethod(3, 100, 1.0e-6, nothing)

julia> card.inputs
7-element Vector{String}:
 "wind_10m"
 "wind_20m"
 "temperature_10m"
 "temperature_20m"
 "precipitation"
 "irradiance"
 "humidity"
```
"""
function Card(d::AbstractDict)
    type::String = d["type"]
    config = CARD_CONFIGS[type]
    return config(d)
end

"""
    Card(d::AbstractDict, params::AbstractDict; recursive::Integer = 1)

Generate a [`Card`](@ref) based on a _parametric_ configuration dictionary `d`
and parameter dictionary `params`.
The value `recursive` denotes how many times to process replaced variables.
Use `recursive = 0` to avoid recursion altogether and a large number to allow
arbitrary recursion.

!!! warning
    Parametric configurations are experimental, the API is not yet
    fully stabilized and documented.

## Current implementation

- Variable substitution based on key `-v`
- Splicing variable substitution based on key `-s`
- Range substitution based on key `-r`
- Splicing joining with underscore based on key `-j`

## Examples

Dictionaries are given in TOML format for clarity.

Initial card configuration `d`:

```toml
type = "cluster"
method = "kmeans"
method_options = {classes = {"-v" = "nclasses"}}
inputs = [
    {"-j" = ["component", {"-r" = 3}]},
    {"-j" = [["wind", "temperature"], ["10m", "20m"]]},
    {"-s" = "additional_input_vars"},
    "humidity"
]
```

Parameter dictionary `params`:

```toml
nclasses = 3
additional_input_vars = ["precipitation", "irradiance"]
```

Final card configuration `Pipelines.apply_helpers(d, params; recursive)`:

```toml
method = "kmeans"
classes = 3
type = "cluster"
inputs = [
    "component_1",
    "component_2",
    "component_3",
    "wind_10m",
    "wind_20m",
    "temperature_10m",
    "temperature_20m",
    "precipitation",
    "irradiance",
    "humidity"
]
```
"""
function Card(d::AbstractDict, params::AbstractDict; recursive::Integer = 1)
    return Card(apply_helpers(d, params; recursive))
end

# TODO: document

function sorting_vars end
function grouping_vars end
function input_vars end
function target_vars end
function weight_var end
function partition_var end
function output_vars end

function inverse_input_vars end
function inverse_output_vars end

## Accessor functions

"""
    get_inputs(c::Card; invert::Bool = false, train::Bool = !invert)::Vector{String}

Return the list of inputs for a given card.
"""
function get_inputs(c::Card; invert::Bool = false, train::Bool = !invert)::Vector{String}
    always_include = (sorting_vars(c), grouping_vars(c))
    return if invert
        union(always_include..., inverse_input_vars(c))
    elseif train
        union(
            always_include...,
            input_vars(c),
            target_vars(c),
            to_stringlist(weight_var(c)),
            to_stringlist(partition_var(c)),
        )
    else
        union(always_include..., input_vars(c))
    end
end

"""
    get_outputs(c::Card; invert::Bool = false)::Vector{String}

Return the list of outputs for a given card.
"""
function get_outputs(c::Card; invert::Bool = false)::Vector{String}
    return invert ? inverse_output_vars(c) : output_vars(c)
end

function get_metadata end

get_label(c::Card) = c.label

## Training and evaluation

"""
    invertible(c::Card)::Bool

Return `true` for invertible cards, `false` otherwise.
"""
invertible(::Card) = false

"""
    train(repository::Repository, card::Card, source; schema = nothing)::CardState

Return a trained model for a given `card` on a table `table` in the database `repository.db`.
"""
function train end

"""
    evaluate(
        repository::Repository,
        card::Card,
        state::CardState,
        (source, destination)::Pair,
        id::AbstractString;
        schema = nothing
    )

Replace table `destination` in the database `repository.db` with the outcome of executing the `card`
on the table `source`.
The new table `destination` will have an additional column `id`, to be joined with the row
number of the original table.

Here, `state` represents the result of `train(repository, card, source; schema)`.
See also [`train`](@ref).
"""
function evaluate end

"""
    report(repository::Repository, nodes::AbstractVector)

Create default reports for all `nodes` referring to a given `repository`.
Each node must be of type `Node`.
"""
function report(repository::Repository, nodes::AbstractVector)
    return report.(Ref(repository), get_card.(nodes), get_state.(nodes))
end

"""
    report(::Repository, ::Card, ::CardState)

Overload this method (replacing `Card` with a specific card type)
to implement a default report for a given card type.
"""
report(::Repository, ::Card, ::CardState) = nothing

"""
    visualize(repository::Repository, nodes::AbstractVector)

Create default visualizations for all `nodes` referring to a given `repository`.
Each node must be of type `Node`.
"""
function visualize(repository::Repository, nodes::AbstractVector)
    return visualize.(Ref(repository), get_card.(nodes), get_state.(nodes))
end

"""
    visualize(::Repository, ::Card, ::CardState)

Overload this method (replacing `Card` with a specific card type)
to implement a default visualization for a given card type.
"""
visualize(::Repository, ::Card, ::CardState) = nothing

## Define new cards

"""
    @kwdef struct CardConfig{T <: Card}
        key::String
        label::String
        needs_targets::Bool
        needs_order::Bool
        allows_weights::Bool
        allows_partition::Bool
        widget_configs::StringDict = StringDict()
        methods::StringDict = StringDict()
    end

Configuration used to register a card.
"""
@kwdef struct CardConfig{T <: Card}
    key::String
    label::String
    needs_targets::Bool
    needs_order::Bool
    allows_weights::Bool
    allows_partition::Bool
    widget_configs::StringDict = StringDict()
    methods::StringDict = StringDict()
end

function CardConfig{T}(c::AbstractDict) where {T <: Card}
    key::String = c["key"]
    label::String = c["label"]
    needs_targets::Bool = c["needs_targets"]
    needs_order::Bool = c["needs_order"]
    allows_weights::Bool = c["allows_weights"]
    allows_partition::Bool = c["allows_partition"]
    widget_configs::StringDict = c["widget_configs"]
    methods::StringDict = get(c, "methods", StringDict())
    return CardConfig{T}(;
        key,
        label,
        needs_targets,
        needs_order,
        allows_weights,
        allows_partition,
        widget_configs,
        methods
    )
end

card_type(::CardConfig{T}) where {T <: Card} = T

(config::CardConfig)(c::AbstractDict) = card_type(config)(c)

const CARD_CONFIGS = OrderedDict{String, CardConfig}()

## Generate widgets

function card_widgets(options::AbstractDict = StringDict())
    widgets = CardWidget[]
    for (k, config) in pairs(CARD_CONFIGS)
        specific_options = mergewith(
            merge,
            WIDGET_CONFIGS[],
            config.widget_configs,
            get(options, k, StringDict())
        )
        push!(widgets, CardWidget(config, specific_options))
    end
    return widgets
end

"""
    register_card(config::CardConfig)

Set a given card configuration as globally available.

See also [`CardConfig`](@ref).
"""
function register_card(config::CardConfig)
    CARD_CONFIGS[config.key] = config
    return
end

## Helpers

card_label(c::AbstractDict, config::CardConfig) = get(c, "label", config.label)
