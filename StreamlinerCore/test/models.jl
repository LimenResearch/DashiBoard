@testset "basic" begin
    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "scheduled.toml"))
    (; device, batchsize, optimizer, schedules, stoppers) = training
    m, loss = model(train_regression_data.templates), model.loss
    @test loss isa StreamlinerCore.Metric{typeof(Flux.Losses.logitcrossentropy)}

    input = rand(Float32, 28, 28, 1, 32) |> device # dummy MNIST-like input
    target = rand(Float32, 10, 32) |> device # dummy MNIST-like output
    @test optimizer == Adam()
    @test schedules[:eta] == CosAnneal(l0 = 1.0e-2, l1 = 1.0e-3, period = 10, restart = true)
    @test batchsize == 32
    @test length(stoppers) == 2
    @test device == CPUDevice()

    r = device(m)((; input, target))
    prediction = r.prediction
    @test size(prediction) == size(target)
    @test isfinite(loss(r))

    @test length(m.model) == 5
    @test m.model[1] isa Conv && m.model[2] isa Conv
    @test m.model[3] isa MaxPool
    @test m.model[4] === flatten
    @test m.model[5] isa Dense

    @test length(model.regularizations) == 2
    @test model.regularizations[1] == StreamlinerCore.Regularization(StreamlinerCore.l1, 0.01f0)
    @test model.regularizations[2] == StreamlinerCore.Regularization(StreamlinerCore.l2, 0.1f0)

    @test_throws ArgumentError StreamlinerCore.architecture(StreamlinerCore.BasicSpec, Dict{Symbol, Any}())
end

@testset "basic template" begin
    vars = Dict(
        "kernel_size" => 5,
        "sigma" => "relu",
        "iterations" => 2,
        "optimizer" => "Adam",
        "eta" => 1.0e-2
    )

    model = Model(parser, joinpath(static_dir, "model", "conv.template.toml"), vars)
    training = Training(parser, joinpath(static_dir, "training", "batched.template.toml"), vars)
    (; device, batchsize, optimizer, schedules, stoppers) = training
    m, loss = model(train_regression_data.templates), model.loss
    @test loss isa StreamlinerCore.Metric{typeof(Flux.Losses.logitcrossentropy)}

    input = rand(Float32, 28, 28, 1, 32) |> device # dummy MNIST-like input
    target = rand(Float32, 10, 32) |> device # dummy MNIST-like output
    @test optimizer == Adam(eta = 1.0e-2)
    @test isempty(schedules)
    @test batchsize == 32
    @test isempty(stoppers)
    @test device == CPUDevice()

    r = device(m)((; input, target))
    prediction = r.prediction
    @test size(prediction) == size(target)
    @test isfinite(loss(r))

    @test length(m.model) == 5
    @test m.model[1] isa Conv && m.model[2] isa Conv
    @test m.model[3] isa MaxPool
    @test m.model[4] === flatten
    @test m.model[5] isa Dense
end

@testset "vae" begin
    model = Model(parser, joinpath(static_dir, "model", "vae.toml"))
    training = Training(parser, joinpath(static_dir, "training", "batched.toml"))
    (; device, batchsize, optimizer, schedules, stoppers) = training
    m, loss = model(train_autoencoder_data.templates), model.loss
    @test loss isa StreamlinerCore.VAELoss

    input = rand(Float32, 28, 28, 1, 32) |> device # dummy MNIST-like input
    target = input
    @test optimizer == Adam(eta = 0.01)
    @test isempty(schedules)
    @test batchsize == 32
    @test length(stoppers) == 0
    @test device == CPUDevice()

    r = device(m)((; input, target))
    prediction = r.prediction
    @test size(prediction) == size(target)
    @test isfinite(loss(r))

    @test length(m.embedding) == 3
    @test all(l -> l isa Conv, m.embedding.layers)
    @test length(m.projection) == 4
    @test all(l -> l isa ConvTranspose, m.projection.layers[1:2])
    @test m.projection.layers[4] == StreamlinerCore.Upsample(NNlib.upsample_linear, (28, 28), false)

    @test_throws ArgumentError StreamlinerCore.architecture(StreamlinerCore.VAESpec, Dict{Symbol, Any}())
end

@testset "predictor" begin
    model = Model(parser, joinpath(static_dir, "model", "predictor.toml"))
    training = Training(parser, joinpath(static_dir, "training", "batched.toml"))
    (; device, batchsize, optimizer, schedules, stoppers) = training
    m, loss = model(train_prediction_data.templates), model.loss
    @test loss isa StreamlinerCore.Metric{typeof(Flux.Losses.mse)}

    input = rand(Float32, 28, 28, 1, 32) |> device # dummy MNIST-like input
    target = rand(Float32, 6, 1, 1, 32) |> device

    r = device(m)((; input, target))
    prediction = r.prediction
    @test size(prediction) == size(target)
    @test isfinite(loss(r))

    @test length(m.model) == 5
    @test m.model[1] isa Conv && m.model[2] isa Conv
    @test m.model[3] isa MaxPool
    @test m.model[4] isa MeanPool
    @test m.model[5] == StreamlinerCore.Upsample(NNlib.upsample_linear, (6, 1), false)
end
