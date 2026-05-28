vars = [
    "No", "year", "month", "day", "hour", "pm2.5",
    "DEWP", "TEMP", "PRES", "cbwd", "Iws", "Is", "Ir",
]
ext_vars = vcat(vars, ["partition"])

function _pipeline_schema_validate(schema, conf)
    @test JSONSchema.validate(schema, conf) === nothing
    @test JSONSchema.validate(schema, get_metadata(Card(conf))) === nothing
    return
end

function _pipeline_schema_invalidate(schema, conf)
    @test JSONSchema.validate(schema, conf) !== nothing
    return
end

@testset "split schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "split.json"))
    schema = Pipelines.json_schema(SplitCard, vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["percentile"])
    _pipeline_schema_validate(schema, d["tiles"])
    _pipeline_schema_validate(schema, d["tiles2"])
    _pipeline_schema_validate(schema, d["tiles3"])
    _pipeline_schema_invalidate(schema, d["unsorted"])
end

@testset "window_function schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "window_function.json"))
    schema = Pipelines.json_schema(WindowFunctionCard, vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["percent_rank"])
    _pipeline_schema_validate(schema, d["rank"])
    _pipeline_schema_validate(schema, d["row_number"])
    _pipeline_schema_invalidate(schema, d["no_output"])
end

@testset "rescale schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "rescale.json"))
    schema = Pipelines.json_schema(RescaleCard, vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["zscore"])
    _pipeline_schema_validate(schema, d["zscore2"])
    _pipeline_schema_validate(schema, d["maxabs"])
    _pipeline_schema_validate(schema, d["minmax"])
    _pipeline_schema_validate(schema, d["log"])
    _pipeline_schema_validate(schema, d["logistic"])
    _pipeline_schema_invalidate(schema, d["wrong_method"])
end

@testset "cluster schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "cluster.json"))
    schema = Pipelines.json_schema(ClusterCard, vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["kmeans"])
    _pipeline_schema_validate(schema, d["dbscan"])
    _pipeline_schema_validate(schema, d["dbscan_nullable"])
    _pipeline_schema_invalidate(schema, d["wrong_input"])
end

@testset "dimensionality reduction schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "dimensionality_reduction.json"))
    schema = Pipelines.json_schema(DimensionalityReductionCard, ext_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["pca"])
    _pipeline_schema_validate(schema, d["ppca"])
    _pipeline_schema_validate(schema, d["factoranalysis"])
    _pipeline_schema_validate(schema, d["mds"])
    _pipeline_schema_invalidate(schema, d["no_components"])
end

@testset "glm" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "glm.json"))
    schema = Pipelines.json_schema(GLMCard, ext_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["hasPartition"])
    _pipeline_schema_validate(schema, d["hasWeights"])

    schema = Pipelines.json_schema(MixedModelCard, ext_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["isMixed"])
    _pipeline_schema_validate(schema, d["isMixedHasWeights"])
end
