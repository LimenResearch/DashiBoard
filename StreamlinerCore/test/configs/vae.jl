function test_vae(dir)
    println()
    @info "Starting MNIST training of convolutional network using Variational Auto Encoder"

    model = Model(parser, joinpath(static_dir, "model", "vae.toml"))
    training = Training(parser, joinpath(static_dir, "training", "batched.toml"))
    streaming = Streaming(parser, joinpath(static_dir, "streaming.toml"))

    println(StreamlinerCore.summarize(model, train_regression_data, training))

    wts = joinpath(dir, "wts.jld2")
    result = train(wts, model, train_autoencoder_data, training)

    @info "Completed MNIST training of convolutional network using Variational Auto Encoder"
    @show result.stats
    println()

    result′ = validate(wts, model, test_autoencoder_data, streaming)

    @info "Completed MNIST validation of convolutional network"
    @show result′.stats
    println()

    res = evaluate(wts, model, test_autoencoder_data, streaming)
    @show size.(getproperty.(res, :prediction))
    println()
end
