function test_optim(prefix)
    println()
    @info "Starting MNIST training of convolutional network using Optim.jl"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "optim.toml"))

    entry = train(model, training, train_regression_data; prefix)

    @info "Completed MNIST training of convolutional network using Optim.jl"
    @show entry.result.filename
    @show entry.result.stats
    println()

    entry′ = validate(parser, test_regression_data, entry)

    @info "Completed MNIST validation of convolutional network"
    @show entry′.result.stats
    println()

    res = evaluate(parser, test_regression_data, entry)
    @show size.(getproperty.(res, :prediction))
    println()
end
