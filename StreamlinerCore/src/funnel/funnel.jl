abstract type Funnel end

@kwdef struct DBFunnel <: Funnel
    order_by::Vector{String}
    inputs::Vector{RichColumn}
    input_paths::Union{String, Nothing} = nothing
    targets::Vector{RichColumn}
    target_paths::Union{String, Nothing} = nothing
end

function db_funnel(c::AbstractDict)
    order_by::Vector{String} = get(c, "order_by", String[])
    inputs::Vector{RichColumn} = RichColumn.(get(c, "inputs", []))
    input_paths::Union{String, Nothing} = get(c, "input_paths", nothing)
    targets::Vector{RichColumn} = RichColumn.(get(c, "targets", []))
    target_paths::Union{String, Nothing} = get(c, "target_paths", nothing)
    return DBFunnel(order_by, inputs, input_paths, targets, target_paths)
end

function get_metadata(dbf::DBFunnel)
    return StringDict(
        "order_by" => dbf.order_by,
        "inputs" => get_metadata.(dbf.inputs),
        "input_paths" => dbf.input_paths,
        "targets" => get_metadata.(dbf.targets),
        "target_paths" => dbf.target_paths,
    )
end
