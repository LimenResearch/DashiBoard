@testset "metadata split" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "split.json"))

    config = d["percentile"]
    card = Pipelines.Card(config)
    metadata = Pipelines.get_metadata(card)
    for k in ["type", "method", "order_by", "by", "output", "percentile"]
        @test metadata[k] == config[k]
    end
    @test metadata["label"] == "Split"
    card2 = Pipelines.Card(metadata)
    @test card.splitter == card2.splitter

    config = d["tiles"]
    card = Pipelines.Card(config)
    metadata = Pipelines.get_metadata(card)
    for k in ["type", "method", "order_by", "by", "output", "tiles"]
        @test metadata[k] == config[k]
    end
    @test metadata["label"] == "Split"
    card2 = Pipelines.Card(metadata)
    @test card.splitter == card2.splitter
end

@testset "metadata rescale" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "rescale.json"))

    config = d["zscore"]
    card = Pipelines.Card(config)
    metadata = Pipelines.get_metadata(card)
    for k in ["type", "method", "by", "inputs", "targets", "suffix"]
        @test metadata[k] == config[k]
    end
    @test metadata["label"] == "Rescale"
    @test isnothing(metadata["partition"])
    @test metadata["suffix"] == "rescaled"
    @test isnothing(metadata["target_suffix"])
    card2 = Pipelines.Card(metadata)
    @test card.rescaler == card2.rescaler

    config = d["zscore_flipped"]
    card = Pipelines.Card(config)
    metadata = Pipelines.get_metadata(card)
    for k in ["type", "method", "inputs", "targets", "suffix", "target_suffix"]
        @test metadata[k] == config[k]
    end
    @test metadata["label"] == "Rescale"
    @test metadata["by"] == String[]
    @test isnothing(metadata["partition"])
    @test metadata["suffix"] == "rescaled"
    card2 = Pipelines.Card(metadata)
    @test card.rescaler == card2.rescaler
end

@testset "metadata cluster" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "cluster.json"))

    config = d["kmeans"]
    card = Pipelines.Card(config)
    metadata = Pipelines.get_metadata(card)
    for k in ["type", "method", "inputs", "output", "method_options"]
        @test metadata[k] == config[k]
    end
    @test metadata["label"] == "Cluster"
    @test isnothing(metadata["partition"])
    card2 = Pipelines.Card(metadata)
    @test card.clusterer == card2.clusterer
end

@testset "metadata dimensionality reduction" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "dimres.json"))

    config = d["pca"]
    card = Pipelines.Card(config)
    metadata = Pipelines.get_metadata(card)
    for k in ["type", "method", "inputs", "n_components", "partition"]
        @test metadata[k] == config[k]
    end
    @test metadata["label"] == "Dimensionality Reduction"
    @test metadata["output"] == "component"
    @test isempty(metadata["method_options"])
    card2 = Pipelines.Card(metadata)
    @test card.projector == card2.projector

    config = d["ppca"]
    card = Pipelines.Card(config)
    metadata = Pipelines.get_metadata(card)
    for k in ["type", "method", "inputs", "n_components", "method_options", "partition"]
        @test metadata[k] == config[k]
    end
    @test metadata["label"] == "Dimensionality Reduction"
    @test metadata["output"] == "component"
    card2 = Pipelines.Card(metadata)
    @test card.projector == card2.projector
end

@testset "metadata glm" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "glm.json"))

    config = d["hasPartition"]
    card = Pipelines.Card(config)
    metadata = Pipelines.get_metadata(card)
    for k in ["type", "inputs", "target", "partition", "distribution", "link"]
        @test metadata[k] == config[k]
    end
    @test metadata["label"] == "GLM"
    @test metadata["suffix"] == "hat"
    @test isempty(metadata["link_params"])
    card2 = Pipelines.Card(metadata)
    @test card.link == card2.link
    @test card.distribution == card2.distribution
    @test card.formula == card2.formula
end

@testset "metadata interp" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "interp.json"))

    config = d["constant"]
    card = Pipelines.Card(config)
    metadata = Pipelines.get_metadata(card)
    fields = [
        "type", "method", "input", "targets",
        "extrapolation_left", "extrapolation_right",
        "dir", "partition",
    ]
    for k in fields
        @test metadata[k] == config[k]
    end
    @test metadata["label"] == "Interpolation"
    @test metadata["suffix"] == "hat"
end

@testset "metadata gaussian encoding" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "gaussian.json"))

    config = d["identity"]
    card = Pipelines.Card(config)
    metadata = Pipelines.get_metadata(card)
    fields = [
        "type", "method", "input", "n_modes", "max",
        "lambda", "suffix",
    ]
    for k in fields
        @test metadata[k] == config[k]
    end
    @test metadata["label"] == "Gaussian Encoding"
end

@testset "metadata streamliner" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "streamliner.json"))
    # TODO
end

@testset "metadata wild" begin
    _train(wc, t, id; weights = nothing) = nothing
    function _evaluate(wc, model, t, id)
        return Pipelines.SimpleTable(k => zeros(length(id)) for k in wc.outputs), id
    end
    card_config = CardConfig{WildCard{_train, _evaluate}}(
        key = "trivial",
        label = "Trivial",
        needs_targets = false,
        needs_order = false,
        allows_partition = false,
        allows_weights = false
    )
    Pipelines.register_card(card_config)
    # TODO
end
