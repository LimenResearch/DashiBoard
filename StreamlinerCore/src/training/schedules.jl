function get_schedule(schedule_metadata::AbstractDict)
    params = make(SymbolDict, schedule_metadata)
    name = pop!(params, :name)
    return PARSER[].schedules[name](; params...)
end

function get_schedules(metadata::AbstractDict)::SymbolDict
    schedules = make(SymbolDict, get_config(metadata, "schedules"))
    map!(get_schedule, values(schedules))
    return schedules
end

function adjust_params!(optimizer, schedules::SymbolDict, N)
    if !isempty(schedules)
        params = (k => schedule(N) for (k, schedule) in pairs(schedules))
        adjust!(optimizer; params...)
    end
    return
end
