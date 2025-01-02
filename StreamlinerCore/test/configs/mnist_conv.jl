function test_mnist_conv(outputdir)
    println()
    @info "Starting MNIST training of convolutional network"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "scheduled.toml"))

    # Instantiate a model to inspect architecture / parameters
    # Check data volume
    println(StreamlinerCore.summarize(model, training, train_regression_data))

    result = train(model, training, train_regression_data; outputdir)

    @info "Completed MNIST training of convolutional network"
    @show StreamlinerCore.get_filename(result)
    @show result.stats
    println()

    @test StreamlinerCore.has_weights(result)

    finetune(model, training, train_regression_data, result; outputdir, resume = true)
    @info "Finetuned training"

    result′ = validate(model, training, test_regression_data, result)
    @test !StreamlinerCore.has_weights(result′)

    @info "Completed MNIST validation of convolutional network"
    @show result.stats
    println()

    res = evaluate(model, training, test_regression_data, result)
    @show size.(getproperty.(res, :prediction))
    println()

    # Load trained model using optimal weights
    # Can be used as alternative to `evaluate` below
    m′ = loadmodel(model, training, test_regression_data, result)
    @info "Trained model"
    @show m′
    println()

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "null.toml"))

    result = train(model, training, train_regression_data; outputdir)
    @test !StreamlinerCore.has_weights(result)
end
