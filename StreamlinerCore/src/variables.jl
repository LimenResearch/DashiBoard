# Basic templating engine

is_variable(d::AbstractDict) = length(d) == 1 && only(keys(d)) == "-v"
get_variable(vars::AbstractDict, d::AbstractDict) = vars[only(values(d))]

function replace_variables(d::AbstractDict{K}, vars::AbstractDict) where {K}
    is_variable(d) && return get_variable(vars, d)
    d′ = Dict{K, Any}(d)
    map!(Fix2(replace_variables, vars), values(d′))
    return d′
end

replace_variables(v::AbstractVector, vars::AbstractDict) = map(Fix2(replace_variables, vars), v)

replace_variables(x, _) = x
