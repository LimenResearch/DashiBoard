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
    type = d["type"]
    return CARD_TYPES[type](d)
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

const CARD_LABELS = OrderedDict{String, String}()
const CARD_TYPES = OrderedDict{String, Type}()

# Generate widgets and widget configurations

function card_widget(d::AbstractDict, key::AbstractString; kwargs...)
    return @with WIDGET_CONFIG => merge(d["general"], d[key]) begin
        card = CARD_TYPES[key]
        CardWidget(card; kwargs...)
    end
end

function card_configurations(options::AbstractDict = Dict())
    d = Dict{String, AbstractDict}("general" => parse_toml_config("general"))
    for (k, v) in pairs(CARD_TYPES)
        # At the moment, `WildCard`s don't have config files
        d[k] = (v <: WildCard) ? StringDict() : parse_toml_config(k)
    end

    return [card_widget(d, k; get(options, k, (;))...) for k in keys(CARD_TYPES)]
end

function register_card(name::AbstractString, label::AbstractString, ::Type{T}) where {T <: Card}
    CARD_LABELS[name] = label
    CARD_TYPES[name] = T
    return
end

_card_type(::Type{T}) where {T <: Card} = findfirst(Fix1(<:, T), CARD_TYPES)
_card_type(c::T) where {T <: Card} = _card_type(T)

card_label(c::Card) = CARD_LABELS[_card_type(c)]
