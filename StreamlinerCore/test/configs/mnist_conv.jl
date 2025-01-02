function test_mnist_conv(outputdir)
    println()
    @info "Starting MNIST training of convolutional network"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "scheduled.toml"))

    # Instantiate a model to inspect architecture / parameters
    # Check data volume
    println(StreamlinerCore.summarize(model, training, train_regression_data))

    result = train(model, training, train_regression_data; outputdir)
    @test StreamlinerCore.has_weights(result)
    @test result.trained

    @info "Completed MNIST training of convolutional network"
    @show StreamlinerCore.get_filename(result)
    @show result.stats
    println()

    result′ = finetune(result, training, train_regression_data; outputdir, resume = true)
    @test result′.trained
    @test result′.resumed

    @info "Finetuned training"

    result′ = validate(result, training, test_regression_data)
    @test !StreamlinerCore.has_weights(result′)
    @test !result′.trained

    @info "Completed MNIST validation of convolutional network"
    @show result′.stats
    println()

    res = evaluate(result, training, test_regression_data)
    @show size.(getproperty.(res, :prediction))
    println()

    # Load trained model using optimal weights
    # Can be used as alternative to `evaluate` below
    m′ = loadmodel(result, training, test_regression_data)
    @info "Trained model"
    @show m′
    println()

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "null.toml"))

    result = train(model, training, train_regression_data; outputdir)
    @test !StreamlinerCore.has_weights(result)
end
