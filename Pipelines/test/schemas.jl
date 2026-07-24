vars = [
    "No", "year", "month", "day", "hour", "pm2.5",
    "DEWP", "TEMP", "PRES", "cbwd", "Iws", "Is", "Ir",
]
split_vars = vcat(vars, ["partition"])
time_vars = vcat(vars, ["date", "time"])

function _filtered_metadata(d::AbstractDict)
    return filter(!isnothing ∘ last, Pipelines.get_metadata(Card(d)))
end

function _pipeline_schema_validate(schema, conf; from_metadata::Bool = true)
    @test JSONSchema.validate(schema, conf) === nothing
    if from_metadata
        # remove nothings as our API requires `nothing` keys to be omitted
        metadata = _filtered_metadata(conf)
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
    _pipeline_schema_invalidate(schema, merge(d["tiles3"], Dict("order_by" => [])))
    _pipeline_schema_invalidate(schema, merge(d["tiles3"], Dict("suffix" => "hat")))
end

@testset "window_function schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "window_function.json"))
    schema = Pipelines.json_schema("window_function", vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["percent_rank"])
    _pipeline_schema_validate(schema, d["rank"])
    _pipeline_schema_validate(schema, d["row_number"])
    no_output = delete!(deepcopy(d["row_number"]), "output")
    _pipeline_schema_invalidate(schema, no_output)
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
    wrong_method = merge(d["logistic"], Dict("method" => Dict("type" => "loggistic")))
    _pipeline_schema_invalidate(schema, wrong_method)
end

@testset "cluster schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "cluster.json"))
    schema = Pipelines.json_schema("cluster", split_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["kmeans"])
    _pipeline_schema_validate(schema, d["dbscan"])
    _pipeline_schema_validate(schema, d["hasPartition"])
    wrong_input = merge(d["dbscan"], Dict("inputs" => ["temp", "PRES"]))
    _pipeline_schema_invalidate(schema, wrong_input)
    spurious_property = deepcopy(d["dbscan"])
    spurious_property["method"]["minneighbors"] = 10
    _pipeline_schema_invalidate(schema, spurious_property)
end

@testset "dimensionality reduction schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "dimensionality_reduction.json"))
    schema = Pipelines.json_schema("dimensionality_reduction", split_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["pca"])
    _pipeline_schema_validate(schema, d["ppca"])
    _pipeline_schema_validate(schema, d["factoranalysis"])
    _pipeline_schema_validate(schema, d["mds"])
    _pipeline_schema_invalidate(schema, merge(d["mds"], Dict("n_components" => 0)))
end

@testset "glm schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "glm.json"))
    schema = Pipelines.json_schema("glm", split_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["hasPartition"])
    _pipeline_schema_validate(schema, d["hasWeights"])
    no_inputs = deepcopy(d["hasWeights"])
    delete!(no_inputs["formula"], "inputs")
    _pipeline_schema_invalidate(schema, no_inputs)

    schema = Pipelines.json_schema("mixed_model", split_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["isMixed"])
    _pipeline_schema_validate(schema, d["isMixedHasWeights"])
    is_mixed_no_grouping = deepcopy(d["isMixedHasWeights"])
    delete!(is_mixed_no_grouping["formula"], "grouping_factor")
    _pipeline_schema_invalidate(schema, is_mixed_no_grouping)
end

@testset "interp schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "interp.json"))
    schema = Pipelines.json_schema("interp", split_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["constant"])
    _pipeline_schema_validate(schema, d["quadratic"])
    wrong_method = deepcopy(d["quadratic"])
    wrong_method["method"]["type"] = "nonsupported"
    _pipeline_schema_invalidate(schema, wrong_method)
end

@testset "gaussian_encoding schema" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian_encoding.json"))
    schema = Pipelines.json_schema("gaussian_encoding", time_vars) |> JSONSchema.Schema
    _pipeline_schema_validate(schema, d["identity"])
    _pipeline_schema_validate(schema, d["dayofweek"])
    _pipeline_schema_validate(schema, d["dayofyear"])
    _pipeline_schema_validate(schema, d["hour"])
    _pipeline_schema_validate(schema, d["minute"])
    zero_lambda = merge(d["identity"], Dict("lambda" => 0))
    _pipeline_schema_invalidate(schema, zero_lambda)
    no_components = merge(d["identity"], Dict("n_components" => 0))
    _pipeline_schema_invalidate(schema, no_components)
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
            m_basic = _filtered_metadata(d["basic"])
            m_classifier = _filtered_metadata(d["classifier"])

            wrong_model = deepcopy(d["classifier"])
            wrong_model["model"]["features"] = -2
            _pipeline_schema_invalidate(schema, wrong_model)

            wrong_training = deepcopy(d["classifier"])
            wrong_training["training"]["iterations"] = -1
            _pipeline_schema_invalidate(schema, wrong_training)

            spurious_property = deepcopy(d["classifier"])
            spurious_property["qualifier"] = "PRES"
            _pipeline_schema_invalidate(schema, spurious_property)

            spurious_model_property = deepcopy(d["classifier"])
            spurious_model_property["model"]["channels"] = 2
            _pipeline_schema_invalidate(schema, spurious_model_property)

            spurious_training_property = deepcopy(d["classifier"])
            spurious_training_property["training"]["tol"] = 1.0e-5
            _pipeline_schema_invalidate(schema, spurious_training_property)
        end
    )

    # consider scenario where configuration files are no longer available
    schema = Pipelines.json_schema("streamliner", split_vars) |> JSONSchema.Schema

    _pipeline_schema_validate(schema, m_basic, from_metadata = false)
    _pipeline_schema_validate(schema, m_classifier, from_metadata = false)

    pop!(m_basic, "model")
    pop!(m_classifier, "training")

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
