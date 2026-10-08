struct RichColumn
    colname::String
    transform_name::String
    transform::Function
end

colname(r::RichColumn) = r.colname

get_metadata(r::RichColumn) = Dict("colname" => r.colname, "transform" => r.transform_name)

RichColumn(r::RichColumn) = r

# A column with the transform registered under `transform_name`; identity when none is named.
function RichColumn(name::AbstractString, transform_name::AbstractString = "identity")
    return RichColumn(name, transform_name, PARSER[].transforms[transform_name])
end

"""
    TransformError(message, path, pointer = nothing)

A funnel was asked to transform a column it cannot. `path` leads to the entry at fault from the
funnel — the map's field, then the column. `pointer` addresses that entry in a document; it is
filled in by whoever knows where the funnel sits in one.
"""
struct TransformError <: Exception
    message::String
    path::Vector{String}
    pointer::Maybe{String}
end

TransformError(message::AbstractString, path::AbstractVector) = TransformError(message, path, nothing)

Base.showerror(io::IO, err::TransformError) = print(io, err.message)

# The field of a funnel holding the transforms of `list`.
transform_field(list::AbstractString) = string(chopsuffix(list, "s"), "_transforms")

"""
    transform_names()

The transforms an author may name for a column. Identity is not among them: it is what a column
gets when nothing is said.
"""
transform_names() = sort!(String[name for name in keys(PARSER[].transforms) if name != "identity"])
