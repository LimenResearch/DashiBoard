# A struct that wraps another and is written flat: the wrapped struct's fields sit beside the
# wrapper's own in one object. Two helpers, so that a wrapper states which field is wrapped and
# writes neither its schema nor its construction by hand.

"""
    flat_IR(T, field, inner)

The schema of `T` written flat: its own tagged fields, then the properties of `inner` in place of
`field`.
"""
function flat_IR(::Type{T}, field::Symbol, inner::ObjectIR) where {T}
    own = ObjectIR(T; except = (field,))
    return ObjectIR(;
        properties = vcat(own.properties, inner.properties),
        constraints = vcat(own.constraints, inner.constraints),
    )
end

"""
    split_config(inner, d) -> (inside, outside)

The entries of `d` that `inner` declares, and the rest — the two halves a flat document is read as.
"""
function split_config(inner::ObjectIR, d::AbstractDict)
    declared = Set(p.key for p in inner.properties)
    inside = StringDict(k => v for (k, v) in pairs(d) if k in declared)
    outside = StringDict(k => v for (k, v) in pairs(d) if !(k in declared))
    return inside, outside
end
