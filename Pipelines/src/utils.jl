to_string_dict(d) = constructfrom(Dict{String, Any}, d)

const METHOD_OPTIONS_REGEX = r"^method_options\.\d+\.(.*)$"
const MODEL_OPTIONS_REGEX = r"^model_options\.\d+\.(.*)$"
const TRAINING_OPTIONS_REGEX = r"^training_options\.\d+\.(.*)$"

function extract_options(c::AbstractDict, r::Regex)
    d = Dict{Symbol, Any}()
    for (k, v) in pairs(c)
        m = match(r, string(k))
        isnothing(m) || (d[Symbol(only(m))] = v)
    end
    return d
end

function extract_options(c::AbstractDict, key::Symbol, r::Regex)
    return get(c, key) do
        extract_options(c, r)
    end
end

function generate_widget(
        conf::AbstractDict,
        type::Symbol,
        name::AbstractString,
        idx::Integer
    )

    key = string(type, "_", "options", ".", idx, ".", conf["key"])
    visible = Dict(string(type) => [name])
    return Widget(key, conf; visible)
end
