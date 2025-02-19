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

function jldserialize(file::Union{IO, AbstractString}, m)
    jldopen(file, "w") do file
        file["model_state"] = m
    end
end

function jldserialize(m)
    io = IOBuffer()
    jldserialize(io, m)
    return take!(io)
end

function jlddeserialize(v::AbstractVector{UInt8})
    jldopen(IOBuffer(v)) do file
        file["model_state"]
    end
end
