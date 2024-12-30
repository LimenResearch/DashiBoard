function test_vae(prefix)
    println()
    @info "Starting MNIST training of convolutional network using Variational Auto Encoder"

    model = Model(parser, joinpath(static_dir, "model", "vae.toml"))
    training = Training(parser, joinpath(static_dir, "training", "batched.toml"))

    println(StreamlinerCore.summarize(model, training, train_regression_data))

    res = train(model, training, train_autoencoder_data; registry, prefix)

    @info "Completed MNIST training of convolutional network using Variational Auto Encoder"
    @show res["result"]["path"]
    @show res["result"]["stats"]
    println()

    entry = find_latest_entry(registry, model, training, train_autoencoder_data)
    @test !isnothing(entry)

    entries = find_all_entries(registry, model, training, train_autoencoder_data)
    @test length(entries) == 1
    @test only(entries) == entry

    res = validate(parser, test_autoencoder_data, entry; registry)

    @info "Completed MNIST validation of convolutional network"
    @show res["result"]["stats"]
    println()

    res = evaluate(parser, test_autoencoder_data, entry; registry)
    @show size.(getproperty.(res, :prediction))
    println()
end
