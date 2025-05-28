function get_schedules(config::AbstractDict)
    schedules = copy(get_config(config, :schedules))
    map!(values(schedules)) do config
        params, name = pop(config, :name)
        return PARSER[].schedules[name](; params...)
    end
    return schedules
end

function adjust_params!(optimizer, schedules::SymbolDict, N)
    if !isempty(schedules)
        params = (k => schedule(N) for (k, schedule) in pairs(schedules))
        adjust!(optimizer; params...)
    end
    return
end
