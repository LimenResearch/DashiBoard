function test_optim(outputdir)
    println()
    @info "Starting MNIST training of convolutional network using Optim.jl"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "optim.toml"))
    streaming = Streaming(parser, joinpath(static_dir, "streaming.toml"))

    result = train(model, train_regression_data, training; outputdir)

    @info "Completed MNIST training of convolutional network using Optim.jl"
    @show StreamlinerCore.get_filename(result)
    @show result.stats
    println()

    result′ = validate(result, test_regression_data, streaming)

    @info "Completed MNIST validation of convolutional network"
    @show result′.stats
    println()

    res = evaluate(result, test_regression_data, streaming)
    @show size.(getproperty.(res, :prediction))
    println()
end
