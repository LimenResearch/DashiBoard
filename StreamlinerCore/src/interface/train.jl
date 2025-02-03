# Result management

"""
    @kwdef struct Result{N}
        iteration::Int
        stats::NTuple{N, Vector{Float64}}
        trained::Bool
        resumed::Maybe{Bool} = nothing
        successful::Maybe{Bool} = nothing
    end

Structure to encode the result of [`train`](@ref), [`finetune`](@ref), or [`validate`](@ref).
Stores configuration of model, metrics, and information on the location of the model weights.
"""
@kwdef struct Result{N}
    iteration::Int
    stats::NTuple{N, Vector{Float64}}
    trained::Bool
    resumed::Maybe{Bool} = nothing
    successful::Maybe{Bool} = nothing
end

Base.eltype(::Type{Result{N}}) where {N} = Pair{String, Any}

Base.length(::Result) = fieldcount(Result)

function Base.iterate(r::Result, i::Int = 1)
    return if i ≤ length(r)
        k = fieldname(Result, i)
        v = getfield(r, i)
        return Pair{String, Any}(String(k), v), i + 1
    else
        return nothing
    end
end

"""
    has_weights(result::Result)

Return `true` if `result` is a successful training result, `false` otherwise.
"""
has_weights(result::Result) = result.trained && result.successful

# Train model via Optimisers.jl or Optim.jl

@kwdef struct Trace
    stats::NTuple{2, Vector{Float64}}
    metrics::Vector{Any}
    iteration::Int
end

format(k::Symbol, x::Number) = @sprintf "%s: %f" string(k) x

function format_metrics(trace::Trace, p::DataPartition.T)
    (; stats, metrics) = trace
    return join(format.(metricname.(metrics), stats[Int(p)]), ", ")
end

function default_callback(m, trace::Trace; gc = true)
    iteration = trace.iteration
    training = format_metrics(trace, DataPartition.training)
    validation = format_metrics(trace, DataPartition.validation)

    println(
        "iteration: ",
        iteration,
        "\ttraining: {",
        training,
        "}", 
        "\tvalidation: {",
        validation,
        "}"
    )

    gc && GC.gc(false)
end

get_valid_loss(stats::NTuple{2, AbstractVector{<:Real}}) = first(stats[Int(DataPartition.validation)])

function finalize_callback(
        dst::AbstractString, (model, device_m)::ModelPair, valid_stream,
        (training, training_state)::TrainingPair,
        (best_N, best_stats), (N, train_stats); callback
    )

    metrics = (model.loss, model.metrics...)
    valid_stats = compute_metrics(metrics, device_m, valid_stream)
    stats = (
        collect(Float64, train_stats),
        collect(Float64, valid_stats),
    )

    trace = Trace(stats = stats, metrics = collect(Any, metrics), iteration = N)
    callback(device_m, trace)

    valid_loss, best_valid_loss = get_valid_loss(stats), get_valid_loss(best_stats)

    if valid_loss < best_valid_loss
        jldopen(dst, "w") do file
            file["model_state"] = Flux.cpu(Flux.state(device_m))
        end
        best_N, best_stats = N, stats
    end

    return any(Fix1(|>, valid_loss), training_state.stoppers), best_N => best_stats
end

function unbatched_train!(
        dst::AbstractString, (model, device_m)::ModelPair, data::AbstractData{2},
        (training, training_state)::TrainingPair,
        (init_N, init_stats)::Pair; callback
    )

    train_streaming = Streaming(training)
    valid_streaming = Streaming(training; shuffle = false)
    train_data = stream(only, data, DataPartition.training, train_streaming)
    valid_data = stream(only, data, DataPartition.validation, valid_streaming)

    # Turn model into a pair consisting of
    # - a flat vector of parameters `θ₀` and
    # - a function `re` to reconstruct the model from the parameters.
    θ₀, re = destructure(device_m)

    ev = Evaluator(re, train_data, model.loss, model.regularizations)
    vars = Ref{Any}(nothing)

    optimizer = training.optimizer
    best = Ref(init_N => init_stats)

    function enriched_callback(trace)
        epoch = trace.iteration
        epoch == 0 && return false
        N = epoch + init_N
        θ = trace.metadata["x"]
        train_stats = compute_metric((vars[].loss, model.metrics...), vars[].output)
        current = N => train_stats
        stop, best[] = finalize_callback(
            dst, model => re(θ), [valid_data], training => training_state,
            best[], current; callback
        )
        return stop
    end

    function fg!(F, G, θ)
        _vars = nothing
        if !isnothing(G)
            _vars, (grad,) = withgradient(ev, θ)
            G .= grad
        end
        if !isnothing(F)
            _vars = @something _vars ev(θ)
            # we use this trick to store outcome in an external container
            vars[] = _vars
            return _vars.objective
        end
    end

    options = Optim.Options(;
        training.iterations, callback = enriched_callback,
        extended_trace = true, training.options...
    )

    # Here, we are saving the weights to the buffer
    Optim.optimize(Optim.only_fg!(fg!), θ₀, optimizer, options)

    return best[]
end

function epoch_train!(
        (model, device_m)::ModelPair,
        train_stream,
        (training, training_state)::TrainingPair,
    )

    nbatches = length(train_stream)

    train_losses = fill(NaN, nbatches)
    train_metrics = map(_ -> fill(NaN, nbatches), model.metrics)

    @withprogress for (nbatch, batch) in enumerate(train_stream)
        ev = Evaluator(batch, model.loss, model.regularizations)
        vars, (grad,) = withgradient(ev, device_m)
        train_loss, train_res = vars.loss, vars.output
        store_metrics!(
            (train_loss, model.metrics...),
            (train_losses, train_metrics...),
            train_res,
            nbatch
        )
        update!(training_state.optimizer, device_m, grad)
        @logprogress nbatch / nbatches
    end
    return map(mean, (train_losses, train_metrics...))
end

function batched_train!(
        dst::AbstractString, (model, device_m)::ModelPair, data::AbstractData{2},
        (training, training_state)::TrainingPair,
        (init_N, init_stats)::Pair; callback
    )

    best = init_N => init_stats

    train_streaming = Streaming(training)
    valid_streaming = Streaming(training; shuffle = false)

    for epoch in 1:training.iterations
        N = epoch + init_N
        adjust_params!(training_state.optimizer, training.schedules, N)
        train_stats = stream(data, DataPartition.training, train_streaming) do train_stream
            epoch_train!(model => device_m, train_stream, training => training_state)
        end
        current = N => train_stats
        stop, best = stream(data, DataPartition.validation, valid_streaming) do valid_stream
            return finalize_callback(
                dst, model => device_m,
                valid_stream, training => training_state,
                best, current;
                callback
            )
        end
        stop && break
    end
    return best
end

function _train(
        (src, dst)::Pair,
        model::Model, data::AbstractData{2}, training::Training;
        init::Maybe{Result} = nothing, callback = default_callback
    )

    device_m = loadmodel(src, model, data, training.device)

    resumed = !isnothing(init)
    init_N, init_stats = if resumed
        init.iteration => init.stats
    else
        nstats = 1 + length(model.metrics)
        # We assume that untrained model has `Inf` loss
        0 => (fill(Inf, nstats), fill(Inf, nstats))
    end

    init_valid_loss = get_valid_loss(init_stats)
    stoppers::Vector{Any} = start.(training.stoppers, init_valid_loss)

    model_pair = model => device_m
    training_state = TrainingState(setup(training.optimizer, device_m), stoppers)
    training_pair = training => training_state

    best_N, best_stats = if is_batched(training)
        batched_train!(dst, model_pair, data, training_pair, init_N => init_stats; callback)
    else
        unbatched_train!(dst, model_pair, data, training_pair, init_N => init_stats; callback)
    end

    best_valid_loss = get_valid_loss(best_stats)
    successful = best_valid_loss < init_valid_loss

    return Result(;
        iteration = best_N,
        stats = best_stats,
        trained = true,
        resumed,
        successful
    )
end

"""
    train(
        filename::AbstractString,
        model::Model, data::AbstractData{2}, training::Training;
        callback = default_callback
    )

Train `model` using the `training` configuration on `data`.
Save the resulting weights in `filename`.

After every epoch, `callback(m, trace)`.

The arguments of `callback` work as follows.
- `m` is the instantiated neural network or machine,
- `trace` is an object encoding additional information, i.e.,
    - `stats` (average of metrics computed so far),
    - `metrics` (functions used to compute `stats`), and
    - `iteration`.
"""
function train(
        filename::AbstractString,
        model::Model, data::AbstractData{2}, training::Training;
        callback = default_callback
    )
    return _train(nothing => filename, model, data, training; callback)
end

"""
    finetune(
        (src, dst)::Pair,
        model::Model, data::AbstractData{2}, training::Training;
        init::Maybe{Result} = nothing, callback = default_callback
    )

Load model encoded in `model` from `src` and retrain it using
the `training` configuration on `data`.
Save the resulting weights in `dst`.

Use `init = result::Result` to restart training where it left off.
The `callback` keyword argument works as in [`train`](@ref).
"""
function finetune(
        (src, dst)::Pair,
        model::Model, data::AbstractData{2}, training::Training;
        init::Maybe{Result} = nothing, callback = default_callback
    )

    return _train(src => dst, model, data, training; init, callback)
end
