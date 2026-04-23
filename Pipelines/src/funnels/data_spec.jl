@kwdef struct DataSpec
    order_by::Vector{String}
    inputs::Vector{RichColumn}
    input_paths::Union{String, Nothing} = nothing
    targets::Vector{RichColumn}
    target_paths::Union{String, Nothing} = nothing
    partition::Union{String, Nothing}
end

function no_partition(ds::DataSpec)
    return DataSpec(;
        ds.order_by,
        ds.inputs,
        ds.input_paths,
        ds.targets,
        ds.target_paths,
        partition = nothing
    )
end

input_names(ds::DataSpec) = SC.colname.(ds.inputs)

target_names(ds::DataSpec) = SC.colname.(ds.targets)

function DataSpec(parser::Parser, c::AbstractDict)
    order_by::Vector{String} = get(c, "order_by", String[])
    inputs::Vector{RichColumn} = RichColumn.((parser,), get(c, "inputs", []))
    input_paths::Union{String, Nothing} = get(c, "input_paths", nothing)
    targets::Vector{RichColumn} = RichColumn.((parser,), get(c, "targets", []))
    target_paths::Union{String, Nothing} = get(c, "target_paths", nothing)
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    return DataSpec(order_by, inputs, input_paths, targets, target_paths, partition)
end

function get_metadata(ds::DataSpec)
    return StringDict(
        "order_by" => ds.order_by,
        "inputs" => SC.get_metadata.(ds.inputs),
        "input_paths" => ds.input_paths,
        "targets" => SC.get_metadata.(ds.targets),
        "target_paths" => ds.target_paths,
        "partition" => ds.partition,
    )
end
