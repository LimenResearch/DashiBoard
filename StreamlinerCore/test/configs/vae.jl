function test_vae(outputdir)
    println()
    @info "Starting MNIST training of convolutional network using Variational Auto Encoder"

    model = Model(parser, joinpath(static_dir, "model", "vae.toml"))
    training = Training(parser, joinpath(static_dir, "training", "batched.toml"))
    streaming = Streaming(parser, joinpath(static_dir, "streaming.toml"))

    println(StreamlinerCore.summarize(model, train_regression_data, training))

    result = train(model, train_autoencoder_data, training; outputdir)

    @info "Completed MNIST training of convolutional network using Variational Auto Encoder"
    @show StreamlinerCore.get_filename(result)
    @show result.stats
    println()

    result′ = validate(result, test_autoencoder_data, streaming)

    @info "Completed MNIST validation of convolutional network"
    @show result′.stats
    println()

    res = evaluate(result, test_autoencoder_data, streaming)
    @show size.(getproperty.(res, :prediction))
    println()
end
