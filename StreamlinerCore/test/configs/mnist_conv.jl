function test_mnist_conv(dir)
    println()
    @info "Starting MNIST training of convolutional network"

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "scheduled.toml"))
    streaming = Streaming(parser, joinpath(static_dir, "streaming", "unshuffled.toml"))

    # Instantiate a model to inspect architecture / parameters
    # Check data volume
    println(StreamlinerCore.summarize(model, train_regression_data, training))

    outputdir = joinpath(dir, "output")
    result = train(outputdir, model, train_regression_data, training)
    @test StreamlinerCore.has_weights(result)
    # loss and accuracy, for training and validation
    @test all(s -> length(s) == 2 && all(isfinite, s) && 0 ≤ s[2] ≤ 1, result.stats)

    @info "Completed MNIST training of convolutional network"
    println()
    stats = StreamlinerCore.stats_tensor(result, outputdir)
    @test size(stats) == (2, 2, 5)
    # the recorded history holds the best epoch where the result says it is
    @test stats[:, :, result.iteration] == hcat(result.stats...)

    # validating the saved weights on the validation partition reproduces the recorded metrics
    valid_data = Data{1}((train_regression_data.streams[2],), train_regression_data.templates)
    @test only(validate(outputdir, model, valid_data, streaming).stats) ≈ result.stats[2]

    outputdir′ = joinpath(dir, "output′")
    result′ = finetune(outputdir => outputdir′, model, train_regression_data, training, init = result)
    # epochs are counted on from the best epoch of the run it resumes, whose metrics are the bar to beat
    @test result′.iterations == result.iteration + training.iterations
    @test result′.stats[2][1] ≤ result.stats[2][1]

    # with a zero learning rate, fine-tuning validates exactly the weights it started from
    frozen = Training(
        parser, joinpath(static_dir, "training", "batched.template.toml"),
        Dict("iterations" => 1, "optimizer" => "Adam", "eta" => 0.0)
    )
    frozen_stats = Ref{Any}()
    callback = (_, trace) -> (frozen_stats[] = trace.stats)
    finetune(outputdir => joinpath(dir, "frozen"), model, train_regression_data, frozen; init = result, callback)
    @test frozen_stats[][2] ≈ result.stats[2]

    @info "Finetuned training"

    # one prediction per test sample, and they are the loaded model's predictions
    res = collect(evaluate(outputdir, model, test_regression_data, streaming))
    prediction = reduce(hcat, [r.prediction for r in res])
    @test size(prediction) == (10, length(test_idxs))
    m′ = loadmodel(outputdir, model, test_regression_data, streaming.device)
    @test m′(only(test_regression_data.streams)).prediction ≈ prediction
    # the loaded weights are the trained ones, not a fresh initialisation
    fresh = loadmodel(model, test_regression_data, streaming.device)
    @test !isapprox(fresh(only(test_regression_data.streams)).prediction, prediction)
    println()

    model = Model(parser, joinpath(static_dir, "model", "conv.toml"))
    training = Training(parser, joinpath(static_dir, "training", "null.toml"))

    result = train(outputdir, model, train_regression_data, training)
    @test !StreamlinerCore.has_weights(result)
    return
end
