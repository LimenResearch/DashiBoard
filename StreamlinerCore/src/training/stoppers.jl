struct Stopper
    method::Any
    patience::Int
    params::SymbolDict
end

function get_stoppers(config::Config)::Vector{Stopper}
    configs = get(config, :stoppers, Config[])
    return get_stopper.(configs)
end

# We change Flux's default `init_score`: starting with `0` may be counter-intuitive
function get_stopper(config::Config)
    params = SymbolDict(config)

    name = pop!(params, :name)
    patience = pop!(params, :patience)

    get!(params, :init_score, Inf)

    return Stopper(PARSER[].stoppers[name], patience, params)
end

start(s::Stopper) = s.method(identity, s.patience; s.params...)
