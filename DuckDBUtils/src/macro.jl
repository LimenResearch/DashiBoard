struct SQLMacro
    name::String
    args::Vector{String}
    def::String
end

function macro_definition(m::SQLMacro)
    return sprint() do io
        print(io, "CREATE TEMP MACRO ")
        print(io, m.name, "(")
        join(io, m.args, ", ")
        print(io, ") AS ")
        print(io, m.def)
        print(io, ";")
    end
end

macro_cleanup(m::SQLMacro) = string("DROP MACRO ", m.name, ";")

function execute_with_macros(
        f, r::Repository, macros,
        q::Union{AbstractString, SQLNode}, params = NamedTuple();
        schema::Union{AbstractString, Nothing} = nothing
    )
    macro_definitions = join(Iterators.map(macro_definition, macros), "\n")
    macro_cleanups = join(Iterators.map(macro_cleanup, macros), "\n")
    return with_connection(r) do con
        _query(Returns(nothing), con, macro_definitions)
        try
            _execute(f, con, q, params; schema)
        finally
            _query(Returns(nothing), con, macro_cleanups)
        end
    end
end
