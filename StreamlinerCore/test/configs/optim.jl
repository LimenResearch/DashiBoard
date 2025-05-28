function test_optim(dir)
    println()
    @info "Starting MNIST training of convolutional network using Optim.jl"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "optim.toml"))
    streaming = Streaming(parser, joinpath(static_dir, "streaming.toml"))

    outputdir = joinpath(dir, "output")
    result = train(outputdir, model, train_regression_data, training)

    @info "Completed MNIST training of convolutional network using Optim.jl"
    @show result.stats
    println()

    result′ = validate(outputdir, model, test_regression_data, streaming)

    @info "Completed MNIST validation of convolutional network"
    @show result′.stats
    println()

    res = evaluate(outputdir, model, test_regression_data, streaming)
    @show size.(getproperty.(res, :prediction))
    println()
    return
end
