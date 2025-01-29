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
    train(repo::Repository, card::AbstractCard, source; schema = nothing)

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
    m = train(repo, card, source; schema)
    evaluate(repo, card, m, source => dest; schema)
    return m
end

function fromdict(::Type{T}, options::AbstractDict) where {T<:AbstractCard}
    return T(; options...)
end
