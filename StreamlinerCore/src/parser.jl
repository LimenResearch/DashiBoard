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

const PARSER = ScopedValue{Parser}()

function Base.map(f, p::Parser, qs::Parser...)
    N = fieldcount(Parser)
    ps = (p, qs...)
    fields = ntuple(N) do n
        getn = Fix2(getfield, n)
        pns = map(getn, ps)
        return f(pns...)
    end
    return Parser(fields...)
end
