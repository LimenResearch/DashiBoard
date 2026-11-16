function test_optim(dir)
    println()
    @info "Starting MNIST training of convolutional network using Optim.jl"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "optim.toml"))
    streaming = Streaming(parser, joinpath(static_dir, "streaming", "unshuffled.toml"))

    outputdir = joinpath(dir, "output")
    result = train(outputdir, model, train_regression_data, training)
    @test result.iterations == 6
    @test StreamlinerCore.has_weights(result)
    @test all(s -> length(s) == 2 && all(isfinite, s), result.stats)

    @info "Completed MNIST training of convolutional network using Optim.jl"
    println()

    # Optim.jl sees each partition whole: validating the saved weights the same way
    # reproduces the recorded metrics
    valid_data = Data{1}((train_regression_data.streams[2],), train_regression_data.templates)
    whole = Streaming(device = cpu, batchsize = nothing)
    @test only(validate(outputdir, model, valid_data, whole).stats) ≈ result.stats[2]

    res = collect(evaluate(outputdir, model, test_regression_data, streaming))
    prediction = reduce(hcat, [r.prediction for r in res])
    @test size(prediction) == (10, length(test_idxs))
    @test all(isfinite, prediction)
    println()
    return
end
