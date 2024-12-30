function test_vae(prefix)
    println()
    @info "Starting MNIST training of convolutional network using Variational Auto Encoder"

    model = Model(parser, joinpath(static_dir, "model", "vae.toml"))
    training = Training(parser, joinpath(static_dir, "training", "batched.toml"))

    println(StreamlinerCore.summarize(model, training, train_regression_data))

    entry = train(model, training, train_autoencoder_data; prefix)

    @info "Completed MNIST training of convolutional network using Variational Auto Encoder"
    @show entry.result.filename
    @show entry.result.stats
    println()

    entry′ = validate(parser, test_autoencoder_data, entry)

    @info "Completed MNIST validation of convolutional network"
    @show entry′.result.stats
    println()

    res = evaluate(parser, test_autoencoder_data, entry)
    @show size.(getproperty.(res, :prediction))
    println()
end
