"""
    abstract type AbstractCard end

Abstract supertype to encompass all possible filters.

Current implementations:

- [`RescaleCard`](@ref),
- [`SplitCard`](@ref),
- [`GLMCard`](@ref).
"""
abstract type AbstractCard end

function inputs end

function outputs end

function train end

function evaluate end

const StringPair = Pair{<:AbstractString, <:AbstractString}

function evaluate(r::AbstractCard, repo::Repository, (source, target)::StringPair; schema = nothing)
    m = train(r, repo, source; schema)
    evaluate(r, m, repo, source => target; schema)
    return m
end
