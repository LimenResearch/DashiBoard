struct Stopper
    method::Any
    patience::Int
    params::SymbolDict
end

function get_stoppers(config::Config)::Vector{Stopper}
    configs = get(config, :stoppers, Config[])
    return get_stopper.(configs)
end

function get_stopper(config::Config)
    params = SymbolDict(config)

    name = pop!(params, :name)
    patience = pop!(params, :patience)

    return Stopper(PARSER[].stoppers[name], patience, params)
end

start(s::Stopper, init_score::Real) = s.method(identity, s.patience; init_score, s.params...)
