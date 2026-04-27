abstract type Funnel end

@kwdef struct DBFunnel <: Funnel
    order_by::Vector{String}
    inputs::Vector{RichColumn}
    input_paths::Union{String, Nothing} = nothing
    targets::Vector{RichColumn}
    target_paths::Union{String, Nothing} = nothing
end

get_helpers(dbf::DBFunnel) = String[]
get_order_by(dbf::DBFunnel) = dbf.order_by

get_inputs(dbf::DBFunnel) = dbf.inputs
get_constant_inputs(dbf::DBFunnel) = String[]
get_input_paths(dbf::DBFunnel) = dbf.input_paths

get_targets(dbf::DBFunnel) = dbf.targets
get_constant_targets(dbf::DBFunnel) = String[]
get_target_paths(dbf::DBFunnel) = dbf.target_paths

function db_funnel(c::AbstractDict)
    order_by::Vector{String} = get(c, "order_by", String[])
    inputs::Vector{RichColumn} = RichColumn.(get(c, "inputs", []))
    input_paths::Union{String, Nothing} = get(c, "input_paths", nothing)
    targets::Vector{RichColumn} = RichColumn.(get(c, "targets", []))
    target_paths::Union{String, Nothing} = get(c, "target_paths", nothing)

    # validation
    if isempty(order_by)
        throw(ArgumentError("User must define sorting variable(s)"))
    end
    if isempty(targets) && isnothing(target_paths)
        throw(ArgumentError("User must define target variable(s) or target paths"))
    end
    if isempty(inputs) && isnothing(input_paths)
        throw(ArgumentError("User must define input variable(s) or input paths"))
    end

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
