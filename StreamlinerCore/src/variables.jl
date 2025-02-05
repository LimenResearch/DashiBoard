# Basic templating engine

variable_name(d::AbstractDict) = length(d) == 1 ? get(d, "-v", nothing) : nothing

replace_variables(vars::AbstractDict) = Fix2(replace_variables, vars)

function replace_variables(d::AbstractDict{K}, vars::AbstractDict) where {K}
    name = variable_name(d)
    return if isnothing(name)
        Dict{K, Any}(k => replace_variables(v, vars) for (k, v) in pairs(d))
    else
        vars[name]
    end
end

replace_variables(v::AbstractVector, vars::AbstractDict) = replace_variables(vars).(v)

replace_variables(x, ::AbstractDict) = x
