lift_transform(s::AbstractString) = PARSER[].transforms[s]

lower_transform(transform) = findfirst(==(transform), PARSER[].transforms)

@tags struct RichColumn
    colname::String
    # FIXME: avoid type instability here, consider `FunctionWrappers`
    # Also consider a more uniform `{"type": transform_name}` API
    transform::Function & (lift = lift_transform, lower = lower_transform)
end

colname(r::RichColumn) = r.colname

get_metadata(r::RichColumn) = DashiBase.to_config(r)

RichColumn(s::AbstractString) = RichColumn((colname = s, transform = ""))

RichColumn(d::Union{NamedTuple, AbstractDict}) = DashiBase.construct(RichColumn, d)
