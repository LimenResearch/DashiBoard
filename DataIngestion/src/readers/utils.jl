const StringList = AbstractVector{<:AbstractString}
const StringStruct = AbstractDict{<:AbstractString, <:AbstractString}

const Maybe{T} = Union{T, Nothing}

print_argument(io::IO, x::Union{Number, AbstractString}) = print(io, to_sql(x))

function print_argument(io::IO, x::AbstractDict)
    print(io, "{")
    join(io, (string(to_sql(k), ": ", to_sql(v)) for (k, v) in pairs(x)), ", ")
    print(io, "}")
    return
end

function print_argument(io::IO, x::AbstractVector)
    print(io, "[")
    join(io, Iterators.map(to_sql, x), ", ")
    print(io, "]")
    return
end

function reader_call(reader::AbstractString, N::Integer, options::AbstractDict)
    return sprint() do io
        print(io, reader)
        print(io, "(")
        print(io, "[")
        join(io, string.('$', 1:N), ", ")
        print(io, "]")
        for (k, v) in pairs(options)
            if !isnothing(v)
                print(io, ", ", k, " = ")
                print_argument(io, v)
            end
        end
        print(io, ")")
    end
end
