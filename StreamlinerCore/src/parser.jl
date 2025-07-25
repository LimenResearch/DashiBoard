# Parsing structure

"""
    Parser(;
        model, layers, sigmas, aggregators, metrics, regularizations,
        optimizers, schedules, stoppers, devices
    )

Collection of dictionaries to performance the necessary conversion from the
user-specified configuration file or dictionary to julia objects.

For most usecases, one should define a default parser

```julia
parser = default_parser()
```

and pass it to [`Model`](@ref) and [`Training`](@ref) upon construction.

A `parser` object is also required to use interface functions that read from the MongoDB:
- [`finetune`](@ref),
- [`loadmodel`](@ref),
- [`validate`](@ref),
- [`evaluate`](@ref).

See [`default_parser`](@ref) for more advanced uses.
"""
@kwdef struct Parser
    models::StringDict = StringDict()
    layers::StringDict = StringDict()
    sigmas::StringDict = StringDict()
    aggregators::StringDict = StringDict()
    metrics::StringDict = StringDict()
    regularizations::StringDict = StringDict()
    optimizers::StringDict = StringDict()
    schedules::StringDict = StringDict()
    stoppers::StringDict = StringDict()
    devices::StringDict = StringDict()
end

Base.copy(p::Parser) = Parser(ntuple(n -> copy(getfield(p, n)), fieldcount(Parser))...)

function combine!(p::Parser, q::Parser)
    for n in 1:fieldcount(Parser)
        merge!(getfield(p, n), getfield(q, n))
    end
    return p
end

macro parsable(T)
    local T′ = esc(T)
    return quote
        function $T′(parser::Parser, metadata::AbstractDict, vars::AbstractDict)
            return $T′(parser, replace_variables(metadata, vars))
        end

        function $T′(parser::Parser, path::AbstractString, vars::AbstractDict)
            metadata::StringDict = TOML.parsefile(path)
            return $T′(parser, metadata, vars)
        end

        function $T′(parser::Parser, path::AbstractString)
            metadata::StringDict = TOML.parsefile(path)
            return $T′(parser, metadata)
        end
    end
end
