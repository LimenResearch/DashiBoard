function test_vae(dir)
    println()
    @info "Starting MNIST training of convolutional network using Variational Auto Encoder"

    model = Model(parser, joinpath(static_dir, "model", "vae.toml"))
    training = Training(parser, joinpath(static_dir, "training", "batched.toml"))
    streaming = Streaming(parser, joinpath(static_dir, "streaming", "unshuffled.toml"))

    println(StreamlinerCore.summarize(model, train_regression_data, training))

    outputdir = joinpath(dir, "output")
    result = train(outputdir, model, train_autoencoder_data, training)
    @test result.iterations == 5
    @test StreamlinerCore.has_weights(result)
    @test all(s -> length(s) == 1 && all(isfinite, s), result.stats)

    @info "Completed MNIST training of convolutional network using Variational Auto Encoder"
    println()

    # validating the saved weights reproduces the recorded loss, up to the sampling noise of the VAE
    valid_data = Data{1}((train_autoencoder_data.streams[2],), train_autoencoder_data.templates)
    valid_loss = only(only(validate(outputdir, model, valid_data, streaming).stats))
    @test isapprox(valid_loss, only(result.stats[2]), rtol = 1.0e-2)
    # and training improved on the untrained model
    fresh = loadmodel(model, valid_data, cpu)
    @test valid_loss < model.loss(fresh(only(valid_data.streams)))

    # one reconstruction per test sample, shaped as the input
    res = collect(evaluate(outputdir, model, test_autoencoder_data, streaming))
    @test all(r -> size(r.prediction)[1:3] == (28, 28, 1), res)
    @test sum(r -> size(r.prediction, 4), res) == length(test_idxs)
    println()
    return
end
