struct Stopper
    method::Any
    patience::Int
    params::SymbolDict
end

function get_stopper(stopper_metadata::AbstractDict)
    params = make(SymbolDict, stopper_metadata)
    name = pop!(params, :name)
    patience = pop!(params, :patience)

    return Stopper(PARSER[].stoppers[name], patience, params)
end

function get_stoppers(metadata::AbstractDict)::Vector{Stopper}
    stopper_metadatas = get_configs(metadata, "stoppers")
    return get_stopper.(stopper_metadatas)
end

start(s::Stopper, init_score::Real) = s.method(identity, s.patience; init_score, s.params...)
