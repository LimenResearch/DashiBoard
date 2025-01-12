function test_mnist_conv(dir)
    println()
    @info "Starting MNIST training of convolutional network"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "scheduled.toml"))
    streaming = Streaming(parser, joinpath(static_dir, "streaming.toml"))

    # Instantiate a model to inspect architecture / parameters
    # Check data volume
    println(StreamlinerCore.summarize(model, train_regression_data, training))

    wts = joinpath(dir, "wts.jld2")
    result = train(wts, model, train_regression_data, training)
    @test StreamlinerCore.has_weights(result)
    @test result.trained

    @info "Completed MNIST training of convolutional network"
    @show result.stats
    println()

    result′ = finetune(wts, model, train_regression_data, training, init = result)
    @test result′.trained
    @test result′.resumed

    @info "Finetuned training"

    result′ = validate(wts, model, test_regression_data, streaming)
    @test !StreamlinerCore.has_weights(result′)
    @test !result′.trained

    @info "Completed MNIST validation of convolutional network"
    @show result′.stats
    println()

    res = evaluate(wts, model, test_regression_data, streaming)
    @show size.(getproperty.(res, :prediction))
    println()

    # Load trained model using optimal weights
    # Can be used as alternative to `evaluate` below
    m′ = loadmodel(wts, model, test_regression_data, streaming.device)
    @info "Trained model"
    @show m′
    println()

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "null.toml"))

    result = train(wts, model, train_regression_data, training)
    @test !StreamlinerCore.has_weights(result)
end
