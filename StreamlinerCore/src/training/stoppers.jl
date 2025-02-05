struct Stopper
    method::Any
    patience::Int
    params::SymbolDict
end

function get_stoppers(config::AbstractDict)::Vector{Stopper}
    configs = get(config, :stoppers, SymbolDict[])
    return get_stopper.(configs)
end

function get_stopper(config::AbstractDict)
    params, name, patience = pop(config, :name, :patience)

    return Stopper(PARSER[].stoppers[name], patience, params)
end

start(s::Stopper, init_score::Real) = s.method(identity, s.patience; init_score, s.params...)
