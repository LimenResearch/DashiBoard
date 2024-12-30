function test_mnist_conv(prefix)
    println()
    @info "Starting MNIST training of convolutional network"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "scheduled.toml"))

    # Instantiate a model to inspect architecture / parameters
    # Check data volume
    println(StreamlinerCore.summarize(model, training, train_regression_data))

    res = train(model, training, train_regression_data; registry, prefix)

    @info "Completed MNIST training of convolutional network"
    @show res["result"]["path"]
    @show res["result"]["stats"]
    println()

    entry = find_latest_entry(registry, model, training, train_regression_data)
    @test !isnothing(entry)
    @test StreamlinerCore.has_weights(entry)
    templates = StreamlinerCore.dict2templates(entry["templates"])
    @test templates.input == Template{Float32, 3}((28, 28, 1))
    @test templates.target == Template{Bool, 1}((10,))

    finetune(parser, train_regression_data, entry; registry, prefix, resume = true)
    @info "Finetuned training"
    entry′ = find_latest_entry(registry, model, training, train_regression_data, entry, resumed = true)
    @test !isnothing(entry′)

    res = validate(parser, test_regression_data, entry; registry)

    entry′ = find_latest_entry(registry, model, training, test_regression_data, entry; trained = false)
    @test !isnothing(entry′)
    @test !StreamlinerCore.has_weights(entry′)

    @info "Completed MNIST validation of convolutional network"
    @show res["result"]["stats"]
    println()

    res = evaluate(parser, test_regression_data, entry; registry)
    @show size.(getproperty.(res, :prediction))
    println()

    # Load trained model using optimal weights
    # Can be used as alternative to `evaluate` below
    templates = get_templates(test_regression_data)
    m′ = loadmodel(parser, templates, entry; registry)
    @info "Trained model"
    @show m′
    println()

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "null.toml"))

    res = train(model, training, train_regression_data; registry, prefix)
    entry′′ = find_latest_entry(registry, model, training, train_regression_data)
    @test !isnothing(entry′′)

    @test !StreamlinerCore.has_weights(entry′′)
end
