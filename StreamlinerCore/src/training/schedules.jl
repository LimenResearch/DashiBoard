function get_schedules(config::Config)
    schedules = SymbolDict(config.schedules)
    map!(values(schedules)) do config
        params = SymbolDict(config)
        name = pop!(params, :name)
        return PARSER[].schedules[name](; params...)
    end
    return schedules
end

function adjust_params!(optimizer, schedules::SymbolDict, N)
    if !isempty(schedules)
        params = (k => schedule(N) for (k, schedule) in pairs(schedules))
        adjust!(optimizer; params...)
    end
end
