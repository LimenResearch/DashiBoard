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

function evaluate end

const StringPair = Pair{<:AbstractString, <:AbstractString}
