function test_vae(outputdir)
    println()
    @info "Starting MNIST training of convolutional network using Variational Auto Encoder"

    model = Model(parser, joinpath(static_dir, "model", "vae.toml"))
    training = Training(parser, joinpath(static_dir, "training", "batched.toml"))

    println(StreamlinerCore.summarize(model, training, train_regression_data))

    result = train(model, training, train_autoencoder_data; outputdir)

    @info "Completed MNIST training of convolutional network using Variational Auto Encoder"
    @show StreamlinerCore.get_filename(result)
    @show result.stats
    println()

    result′ = validate(result, training, test_autoencoder_data)

    @info "Completed MNIST validation of convolutional network"
    @show result′.stats
    println()

    res = evaluate(result, training, test_autoencoder_data)
    @show size.(getproperty.(res, :prediction))
    println()
end
