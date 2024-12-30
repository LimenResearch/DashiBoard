function test_mnist_conv(prefix)
    println()
    @info "Starting MNIST training of convolutional network"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "scheduled.toml"))

    # Instantiate a model to inspect architecture / parameters
    # Check data volume
    println(StreamlinerCore.summarize(model, training, train_regression_data))

    entry = train(model, training, train_regression_data; prefix)

    @info "Completed MNIST training of convolutional network"
    @show entry.result.filename
    @show entry.result.stats
    println()

    @test StreamlinerCore.has_weights(entry)

    finetune(parser, train_regression_data, entry; prefix, resume = true)
    @info "Finetuned training"

    entry′ = validate(parser, test_regression_data, entry)
    @test StreamlinerCore.has_weights(entry′)

    @info "Completed MNIST validation of convolutional network"
    @show entry.result.stats
    println()

    res = evaluate(parser, test_regression_data, entry)
    @show size.(getproperty.(res, :prediction))
    println()

    # Load trained model using optimal weights
    # Can be used as alternative to `evaluate` below
    templates = get_templates(test_regression_data)
    m′ = loadmodel(parser, templates, entry)
    @info "Trained model"
    @show m′
    println()

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "null.toml"))

    entry = train(model, training, train_regression_data; prefix)
    @test !StreamlinerCore.has_weights(entry)
end
