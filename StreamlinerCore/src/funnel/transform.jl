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
    transform_names()

The transforms an author may name for a column. Identity is not among them: it is what a column
gets when nothing is said.
"""
transform_names() = sort!(String[name for name in keys(PARSER[].transforms) if name != "identity"])
