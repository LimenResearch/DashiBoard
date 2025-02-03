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
    train(repo::Repository, card::AbstractCard, source; schema = nothing)::CardState

Return a trained model for a given `card` on a table `table` in the database `repo.db`.
"""
function train end

"""
    evaluate(repo::Repository, card::AbstractCard, m, (source, dest)::Pair; schema = nothing)

Replace table `dest` in the database `repo.db` with the outcome of executing the `card`
on the table `source`.

Here, `m` represents the result of `train(repo, card, source; schema)`.
See also [`train`](@ref).
"""
function evaluate end

function evaluate(repo::Repository, card::AbstractCard, (source, dest)::Pair; schema = nothing)
    state = train(repo, card, source; schema)::CardState
    evaluate(repo, card, state, source => dest; schema)
    return state
end

@kwdef struct CardState
    content::Union{Nothing, Vector{UInt8}} = nothing
    metadata::Dict{String, Any} = Dict{String, Any}()
end

function jldserialize(file::Union{IO, AbstractString}, m)
    jldopen(file, "w") do io
        io["model_state"] = m
    end
end

function jldserialize(m)
    io = IOBuffer()
    jldserialize(io, m)
    return take!(io)
end

function jlddeserialize(v::AbstractVector{UInt8})
    jldopen(IOBuffer(v)) do io
        io["model_state"]
    end
end
