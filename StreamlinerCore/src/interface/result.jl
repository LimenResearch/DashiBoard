# Result management

@kwdef struct Result{N, P, M<:Model}
    model::M
    prefix::P
    uuid::UUID
    iteration::Int
    stats::NTuple{N, Vector{Float64}}
    trained::Bool
    resumed::Maybe{Bool} = nothing
    successful::Maybe{Bool} = nothing
end

Model(r::Result) = r.model

"""
    has_weights(result::Result)

Return `true` if `result` is a successful training result, `false` otherwise.
"""
has_weights(result::Result) = result.trained && result.successful

get_filename(result::Result) = string("model", "-", result.uuid, ".bson")
get_path(result::Result) = joinpath(result.prefix, get_filename(result))

# helpers to load weights

read_state(io::IO) = load(io)
# Fallback for non-standard paths, e.g., S3 paths
read_state(path) = read_state(IOBuffer(read(path)))

write_state(io::IO, state) = bson(io, state)
