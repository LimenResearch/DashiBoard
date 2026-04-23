struct Funnel{W}
    metadata::StringDict
    windowing::W
    variables::Dict{Symbol, Vector{String}}
end

@parsable Funnel

get_metadata(funnel::Funnel) = funnel.metadata

function parse_windowing(windowing_metadata::AbstractDict)
    params = make(SymbolDict, windowing_metadata)
    name = pop!(params, :name, "")

    windowing = PARSER[].windowings[name]
    return windowing(; params...)
end

function Funnel(parser::Parser, metadata::AbstractDict)
    return @with PARSER => parser begin
        windowing = parse_windowing(get(metadata, "windowing", StringDict()))
        variables::Dict{Symbol, Vector{String}} = get(metadata, "variables", StringDict())
        Funnel(metadata, windowing, variables)
    end
end
