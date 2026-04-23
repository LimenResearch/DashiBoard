# TODO: more descriptive name?
# TODO: unit test within StreamlinerCore tests
struct Funnel{W}
    metadata::StringDict
    windowing::W
    helper_variables::Dict{Symbol, Vector{String}}
end

@parsable Funnel

get_metadata(funnel::Funnel) = funnel.metadata

function parse_windowing(windowing_metadata::AbstractDict)
    params = make(SymbolDict, windowing_metadata)
    name = pop!(params, :name, "")

    windowing = PARSER[].windowings[name]
    return windowing(; params...)
end

"""
    Funnel(parser::Parser, metadata::AbstractDict)

    Funnel(parser::Parser, path::AbstractString, [vars::AbstractDict])

Create a `Funnel` object from a configuration dictionary `metadata` or, alternatively,
from a configuration dictionary stored at `path` in TOML format.
The optional argument `vars` is a dictionary of variables the can be used to
fill the template given in `path`.

The `parser::`[`Parser`](@ref) handles conversion from configuration variables to julia objects.

A `Funnel` can be used to convert data from a database table to batches for consumption
by `StreamlinerCore` models.
"""
function Funnel(parser::Parser, metadata::AbstractDict)
    return @with PARSER => parser begin
        windowing = parse_windowing(get(metadata, "windowing", StringDict()))
        helper_variables::Dict{Symbol, Vector{String}} = get(metadata, "variables", StringDict())
        Funnel(metadata, windowing, helper_variables)
    end
end
