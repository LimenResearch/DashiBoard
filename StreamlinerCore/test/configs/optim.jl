function test_optim(dir)
    println()
    @info "Starting MNIST training of convolutional network using Optim.jl"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "optim.toml"))
    streaming = Streaming(parser, joinpath(static_dir, "streaming.toml"))

    wts = joinpath(dir, "wts.jld2")
    result = train(wts, model, train_regression_data, training)

    @info "Completed MNIST training of convolutional network using Optim.jl"
    @show result.stats
    println()

    result′ = validate(wts, model, test_regression_data, streaming)

    @info "Completed MNIST validation of convolutional network"
    @show result′.stats
    println()

    res = evaluate(wts, model, test_regression_data, streaming)
    @show size.(getproperty.(res, :prediction))
    println()
end
