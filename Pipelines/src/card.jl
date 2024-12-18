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

const StringPair = Pair{<:AbstractString, <:AbstractString}

function plan(::AbstractCard, ::Repository, ::AbstractString; schema = nothing)
    return nothing
end

function evaluate(r::AbstractCard, repo::Repository, (source, target)::StringPair; schema = nothing)
    p = plan(r, repo, source; schema)
    evaluate(r, repo, source => target, p; schema)
    return p
end