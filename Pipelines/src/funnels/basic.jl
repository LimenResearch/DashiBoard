@kwdef struct DBData{N} <: AbstractData{N}
    repository::Repository
    schema::Union{String, Nothing}
    table::String
    predictors::Vector{String}
    targets::Vector{String}
    partition::Union{String, Nothing}
end

function StreamlinerCore.get_templates(d::DBData)
    input = Template(Float32, (length(d.predictors),))
    output = Template(Float32, (length(d.targets),))
    return (; input, output)
end

# TODO: understand role of `get_metadata` in the presence of cards?
function StreamlinerCore.get_metadata(d::DBData)
    return Dict(
        "schema" => d.schema,
        "table" => d.table,
        "predictors" => d.predictors,
        "targets" => d.targets,
        "partition" => d.partition
    )
end

function StreamlinerCore.get_nsamples(d::DBData, partition::Int)
    filter = isnothing(d.partition) ? identity : Where(Get(d.partition) .== partition)
    q = From(d.table) |> filter |> Group() |> Select("count" => Agg.count())
    return DBInterface.execute(x -> only(x).count, d.repository, q; d.schema)
end
