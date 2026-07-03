vars = [
    "No", "year", "month", "day", "hour", "pm2.5",
    "DEWP", "TEMP", "PRES", "cbwd", "Iws", "Is", "Ir",
]
split_vars = vcat(vars, ["partition"])
time_vars = vcat(vars, ["date", "time"])

function _pipeline_schema_validate(schema, conf; from_metadata::Bool = true)
    @test JSONSchema.validate(schema, conf) === nothing
    if from_metadata
        # remove nothings as our API requires `nothing` keys to be omitted
        metadata = filter(!isnothing ∘ last, Pipelines.get_metadata(Card(conf)))
        @test JSONSchema.validate(schema, metadata) === nothing
    end
    return
end

function _pipeline_schema_invalidate(schema, conf)
    @test JSONSchema.validate(schema, conf) !== nothing
    return
end

@testset "split schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "split.json"))
    schema = Pipelines.json_schema("split", vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["percentile"])
    _pipeline_schema_validate(schema, d["tiles"])
    _pipeline_schema_validate(schema, d["tiles2"])
    _pipeline_schema_validate(schema, d["tiles3"])
    _pipeline_schema_invalidate(schema, d["unsorted"])
    _pipeline_schema_invalidate(schema, d["spuriousProperty"])
end

@testset "window_function schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "window_function.json"))
    schema = Pipelines.json_schema("window_function", vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["percent_rank"])
    _pipeline_schema_validate(schema, d["rank"])
    _pipeline_schema_validate(schema, d["row_number"])
    _pipeline_schema_invalidate(schema, d["no_output"])
end

@testset "rescale schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "rescale.json"))
    schema = Pipelines.json_schema("rescale", vars) |> JSONSchema.Schema
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
    schema = Pipelines.json_schema("cluster", split_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["kmeans"])
    _pipeline_schema_validate(schema, d["dbscan"])
    _pipeline_schema_validate(schema, d["hasPartition"])
    _pipeline_schema_invalidate(schema, d["wrongInput"])
    _pipeline_schema_invalidate(schema, d["spuriousProperty"])
end

@testset "dimensionality reduction schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "dimensionality_reduction.json"))
    schema = Pipelines.json_schema("dimensionality_reduction", split_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["pca"])
    _pipeline_schema_validate(schema, d["ppca"])
    _pipeline_schema_validate(schema, d["factoranalysis"])
    _pipeline_schema_validate(schema, d["mds"])
    _pipeline_schema_invalidate(schema, d["no_components"])
end

@testset "glm schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "glm.json"))
    schema = Pipelines.json_schema("glm", split_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["hasPartition"])
    _pipeline_schema_validate(schema, d["hasWeights"])
    _pipeline_schema_invalidate(schema, d["noInputs"])

    schema = Pipelines.json_schema("mixed_model", split_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["isMixed"])
    _pipeline_schema_validate(schema, d["isMixedHasWeights"])
    _pipeline_schema_invalidate(schema, d["isMixedNoGrouping"])
end

@testset "interp schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "interp.json"))
    schema = Pipelines.json_schema("interp", split_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["constant"])
    _pipeline_schema_validate(schema, d["quadratic"])
    _pipeline_schema_invalidate(schema, d["wrongMethod"])
end

@testset "gaussian_encoding schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian_encoding.json"))
    schema = Pipelines.json_schema("gaussian_encoding", time_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["identity"])
    _pipeline_schema_validate(schema, d["dayofweek"])
    _pipeline_schema_validate(schema, d["dayofyear"])
    _pipeline_schema_validate(schema, d["hour"])
    _pipeline_schema_validate(schema, d["minute"])
    _pipeline_schema_invalidate(schema, d["zeroLambda"])
end

@testset "streamliner schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "streamliner.json"))
    model_dir = joinpath(@__DIR__, "static", "model")
    training_dir = joinpath(@__DIR__, "static", "training")

    @with(
        Pipelines.MODEL_DIR => model_dir,
        Pipelines.TRAINING_DIR => training_dir,
        begin
            schema = Pipelines.json_schema("streamliner", split_vars) |> JSONSchema.Schema
            _pipeline_schema_validate(schema, d["basic"], from_metadata = false)
            _pipeline_schema_validate(schema, d["classifier"], from_metadata = false)
            m_basic = Pipelines.get_metadata(Card(d["basic"]))
            m_classifier = Pipelines.get_metadata(Card(d["classifier"]))
            _pipeline_schema_invalidate(schema, d["wrongModel"])
            _pipeline_schema_invalidate(schema, d["wrongTraining"])
        end
    )

    # consider scenario where configuration files are no longer available
    schema = Pipelines.json_schema("streamliner", split_vars) |> JSONSchema.Schema

    _pipeline_schema_validate(schema, m_basic, from_metadata = false)
    _pipeline_schema_validate(schema, m_classifier, from_metadata = false)

    pop!(m_basic, "model_metadata")
    pop!(m_classifier, "training_metadata")

    _pipeline_schema_invalidate(schema, m_basic)
    _pipeline_schema_invalidate(schema, m_classifier)
end

@testset "wild schema" begin
    schema = Pipelines.json_schema("trivial", vars) |> JSONSchema.Schema

    single_output = Dict("type" => "trivial", "inputs" => ["month"], "outputs" => ["TEMP"])
    multi_outputs = Dict("type" => "trivial", "inputs" => ["month"], "outputs" => ["TEMP", "PRES"])
    no_output = Dict("type" => "trivial", "inputs" => ["month"], "outputs" => [])
    _pipeline_schema_validate(schema, single_output)
    _pipeline_schema_validate(schema, multi_outputs)
    _pipeline_schema_invalidate(schema, no_output)
end
