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

"""
    abstract type Card end

Abstract supertype to encompass all possible cards.

Current implementations:

- [`SplitCard`](@ref),
- [`RescaleCard`](@ref),
- [`ClusterCard`](@ref),
- [`DimensionalityReductionCard`](@ref),
- [`GLMCard`](@ref),
- [`InterpCard`](@ref),
- [`GaussianEncodingCard`](@ref),
- [`StreamlinerCard`](@ref),
- [`WildCard`](@ref).
"""
abstract type Card end

abstract type StandardCard <: Card end
abstract type SQLCard <: Card end
abstract type StreamingCard <: Card end

"""
    Card(d::AbstractDict)

Generate a [`Card`](@ref) based on a configuration dictionary.
"""
function Card(d::AbstractDict)
    type::String = d["type"]
    config = CARD_CONFIGS[type]
    return config(d)
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

# Construct cards

"""
    @kwdef struct CardConfig{T <: Card}
        key::String
        label::String
        needs_targets::Bool
        needs_order::Bool
        allows_weights::Bool
        allows_partition::Bool
        widgets::StringDict = StringDict()
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
    widgets::StringDict = StringDict()
end

function CardConfig{T}(c::AbstractDict) where {T <: Card}
    key::String = c["key"]
    label::String = c["label"]
    needs_targets::Bool = c["needs_targets"]
    needs_order::Bool = c["needs_order"]
    allows_weights::Bool = c["allows_weights"]
    allows_partition::Bool = c["allows_partition"]
    widgets::StringDict = c["widgets"]
    return CardConfig{T}(;
        key,
        label,
        needs_targets,
        needs_order,
        allows_weights,
        allows_partition,
        widgets
    )
end

(::CardConfig{T})(c::AbstractDict) where {T} = T(c)

const CARD_CONFIGS = OrderedDict{String, CardConfig}()

# Generate widgets and widget configurations

function card_widget(d::AbstractDict, key::AbstractString; kwargs...)
    return @with WIDGET_CONFIG => merge(d["general"], d[key]) begin
        config = CARD_CONFIGS[key]
        CardWidget(config, key; kwargs...)
    end
end

function card_configurations(options::AbstractDict = Dict())
    general_widgets = parse_toml_config("general")
    card_widgets = CardWidget[]
    for (k, config) in pairs(CARD_CONFIGS)
        specific_options = get(options, k, (;))
        @with WIDGET_CONFIG => merge(general_widgets, config.widgets) begin
            push!(card_widgets, CardWidget(config; specific_options...))
        end
    end
    return card_widgets
end

# TODO: improve docs
"""
    register_card(config::CardConfig)

Set a given card configuration as globally available.

See also [`CardConfig`](@ref).
"""
function register_card(config::CardConfig)
    CARD_CONFIGS[config.key] = config
    return
end

card_label(c::Card) = c.label

function card_label(c::AbstractDict)
    return get(c, "label") do
        type::String = c["type"]
        return CARD_CONFIGS[type].label
    end
end
