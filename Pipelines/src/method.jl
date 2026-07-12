## General method type

abstract type AbstractMethod end

function get_metadata(c::AbstractMethod, methods::AbstractDict)
    d = construct(StringDict, c)
    d["type"] = findfirst(Fix1(isa, c), methods)
    return d
end

# Method machinery

macro options(T, methods, default = nothing)
    return quote
        function StructUtils.make(::DashiStyle, ::Type{$(esc(T))}, c)
            S = lift_method(c, $(esc(methods)), default = $(esc(default)))
            return StructUtils.make(DashiStyle(), S, c)
        end

        function StructUtils.make(::DashiStyle, ::Type{$(esc(T))}, c, tags)
            S = lift_method(c, $(esc(methods)), default = $(esc(default)))
            return StructUtils.make(DashiStyle(), S, c, tags)
        end

        function Pipelines.schema_from_type(::Type{$(esc(T))})
            return full_conditional_options_schemas($(esc(methods)), default = $(esc(default)))
        end

        StructUtils.lower(::DashiStyle, c::$(esc(T))) = get_metadata(c, $(esc(methods)))
    end
end
