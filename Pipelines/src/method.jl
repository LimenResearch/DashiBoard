## General method type

abstract type AbstractMethod end

function choose_method(
        d::AbstractDict, methods::AbstractDict;
        default::Union{AbstractString, Nothing} = nothing
    )
    method::String = isnothing(default) ? d["type"] : get(d, "type", default)
    M = get(methods, method, nothing)
    if isnothing(M)
        valid_methods = join(keys(methods), ", ")
        throw(ArgumentError("Found invalid method: '$method'. Valid methods: $valid_methods."))
    end
    return M
end

function get_metadata(c::AbstractMethod, methods::AbstractDict)
    d = to_config(c)
    d["type"] = findfirst(Fix1(isa, c), methods)
    return d
end

# Method machinery

macro options(T, methods, default = nothing)
    return quote
        function StructUtils.make(::DashiStyle, ::Type{$(esc(T))}, c)
            S = choose_method(c, $(esc(methods)), default = $(esc(default)))
            return StructUtils.make(DashiStyle(), S, c)
        end

        function StructUtils.make(::DashiStyle, ::Type{$(esc(T))}, c, tags)
            S = choose_method(c, $(esc(methods)), default = $(esc(default)))
            return StructUtils.make(DashiStyle(), S, c, tags)
        end

        function DashiBase.IR_from_type(::Type{$(esc(T))}, _default)
            local default_option = if isnothing(_default)
                $(esc(default))
            elseif isnothing($(esc(default)))
                findfirst(==(_default), $(esc(methods)))
            elseif _default isa $(esc(methods))[$(esc(default))]
                $(esc(default))
            else
                throw(ArgumentError("Inconsistent defaults"))
            end
            local objects = Dict{String, ObjectIR}(k => ObjectIR(m) for (k, m) in pairs($(esc(methods))))

            return TaggedObjectIR(; objects, default_option)
        end

        StructUtils.lower(::DashiStyle, c::$(esc(T))) = get_metadata(c, $(esc(methods)))
    end
end

# Machinery for simple methods (essentially, enum)
# TODO: consider how to standardize various method implementations

function lift_simple_method(
        d::AbstractDict, methods::AbstractDict;
        default::Union{AbstractString, Nothing} = nothing
    )
    return choose_method(d, methods; default)
end

lower_simple_method(x, methods::AbstractDict) = StringDict("type" => findfirst(==(x), methods))
