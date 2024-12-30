const AbstractContainer = Union{AbstractDict, AbstractVector}

function json_schema(dict::AbstractDict; toplevel = false)
    ks = collect(keys(dict))
    schema = StringDict()
    if !toplevel
        schema["bsonType"] = "object"
        schema["maxProperties"] = length(ks)
        schema["minProperties"] = length(ks)
    end
    schema["required"] = ks
    schema["properties"] = StringDict(k => json_schema(dict[k]) for k in ks)
    return schema
end

function json_schema(v::AbstractVector)
    schema = StringDict()
    schema["bsonType"] = "array"
    schema["maxItems"] = length(v)
    schema["minItems"] = length(v)
    schema["items"] = map(json_schema, v)
    return schema
end

json_schema(::AbstractFloat) = StringDict("bsonType" => "double")
json_schema(::Int64) = StringDict("bsonType" => "long")
json_schema(::Int32) = StringDict("bsonType" => "int")

json_schema(::Bool) = StringDict("bsonType" => "bool")

json_schema(::AbstractString) = StringDict("bsonType" => "string")
json_schema(::BSONObjectId) = StringDict("bsonType" => "objectId")

json_schema(::Nothing) = StringDict("bsonType" => "null")

to_js_key(::AbstractDict, k::AbstractString) = k
to_js_key(a::AbstractVector, i::Integer) = string(i - firstindex(a))

to_query!(query::BSON, x, prefix::AbstractString) = setindex!(query, x, prefix)

function to_query!(query::BSON, d::AbstractContainer, prefix::AbstractString = "")
    for (k, v) in pairs(d)
        suffix = to_js_key(d, k)
        prefix′ = isempty(prefix) ? suffix : prefix * "." * suffix
        to_query!(query, v, prefix′)
    end
    return query
end

function to_query(d::AbstractDict)
    query = BSON("\$jsonSchema" => json_schema(d; toplevel = true))
    return to_query!(query, d)
end
