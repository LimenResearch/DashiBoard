struct RichColumn
    colname::String
    transform_name::String
    transform::Function
end

colname(r::RichColumn) = r.colname

get_metadata(r::RichColumn) = Dict("colname" => r.colname, "transform" => r.transform_name)

function RichColumn(s::Union{AbstractString, AbstractDict})
    column_name::String, transform_name::String =
        s isa AbstractDict ? (s["colname"], s["transform"]) : (s, "")
    transform = PARSER[].transforms[transform_name]
    return RichColumn(column_name, transform_name, transform)
end
