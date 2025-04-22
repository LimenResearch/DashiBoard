"""
    abstract type AbstractCard end

Abstract supertype to encompass all possible filters.

Current implementations:

- [`RescaleCard`](@ref),
- [`SplitCard`](@ref),
- [`GLMCard`](@ref).
"""
abstract type AbstractCard end

"""
    inputs(c::AbstractCard)::OrderedSet{String}

Return the list of inputs for a given card.
"""
function inputs end

"""
    outputs(c::AbstractCard)::OrderedSet{String}

Return the list of outputs for a given card.
"""
function outputs end

"""
    invertible(c::AbstractCard)::Bool

Return `true` for invertible cards, `false` otherwise.
"""
function invertible end

"""
    train(repository::Repository, card::AbstractCard, source; schema = nothing)::CardState

Return a trained model for a given `card` on a table `table` in the database `repository.db`.
"""
function train end

"""
    evaluate(repository::Repository, card::AbstractCard, state::CardState, (source, destination)::Pair; schema = nothing)

Replace table `destination` in the database `repository.db` with the outcome of executing the `card`
on the table `source`.

Here, `state` represents the result of `train(repository, card, source; schema)`.
See also [`train`](@ref).
"""
function evaluate end

function evaluate(repository::Repository, card::AbstractCard, (source, destination)::Pair; schema = nothing)
    state = train(repository, card, source; schema)::CardState
    evaluate(repository, card, state, source => destination; schema)
    return state
end

@kwdef struct CardState
    content::Union{Nothing, Vector{UInt8}} = nothing
    metadata::Dict{String, Any} = Dict{String, Any}()
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
    visualize(repository::Repository, nodes::AbstractVector)

Create default visualizations for all `nodes` referring to a given `repository`.
Each node must be of type `Node`.
"""
function visualize(repository::Repository, nodes::AbstractVector)
    return visualize.(Ref(repository), get_card.(nodes), get_state.(nodes))
end

"""
    visualize(::Repository, ::AbstractCard, ::CardState)

Overload this method (replacing `AbstractCard` with a specific card type)
to implement a default visualization for a given card type.
"""
visualize(::Repository, ::AbstractCard, ::CardState) = nothing
