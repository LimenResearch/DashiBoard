function test_optim(prefix)
    println()
    @info "Starting MNIST training of convolutional network using Optim.jl"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "optim.toml"))

    res = train(model, training, train_regression_data; registry, prefix)

    @info "Completed MNIST training of convolutional network using Optim.jl"
    @show res["result"]["path"]
    @show res["result"]["stats"]
    println()

    entry = find_latest_entry(registry, model, training, train_regression_data)
    @test !isnothing(entry)

    res = validate(parser, test_regression_data, entry; registry)

    @info "Completed MNIST validation of convolutional network"
    @show res["result"]["stats"]
    println()

    res = evaluate(parser, test_regression_data, entry; registry)
    @show size.(getproperty.(res, :prediction))
    println()
end
