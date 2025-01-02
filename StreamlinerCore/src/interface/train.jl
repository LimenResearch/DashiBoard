# Train model via Optimisers.jl or Optim.jl

@kwdef struct Trace
    stats::NTuple{2, Vector{Float64}}
    metrics::Vector{Any}
    iteration::Int
end

format(k::Symbol, x::Number) = @sprintf "%s: %f" string(k) x

function default_callback(m, trace::Trace; gc = true)
    (; stats, metrics, iteration) = trace

    local training = join(format.(metricname.(metrics), stats[Int(DataPartition.training)]), ", ")
    local validation = join(format.(metricname.(metrics), stats[Int(DataPartition.validation)]), ", ")

    print("iteration: $iteration\ttraining: {$training}\tvalidation: {$validation}\n")

    gc && GC.gc(false)
end

function _train(
        io::IO, model′::Union{Model, Result}, training::Training, data::AbstractData{2};
        resume::Bool, callback, outputdir
    )

    device_m = loadmodel(model′, training, data)
    model = Model(model′)

    init = if resume
        model′.iteration => model′.stats
    else
        nstats = 1 + length(model.metrics)
        0 => (fill(Inf, nstats), fill(Inf, nstats))
    end

    stoppers::Vector{Any} = start.(training.stoppers)

    if is_batched(training)
        training_state = TrainingState(Flux.setup(training.optimizer, device_m), stoppers)
        best_N, best_stats = batched_train!(
            io, model => device_m, training => training_state, data, init; callback
        )
    else
        training_state = TrainingState(training.optimizer, stoppers)
        best_N, best_stats = unbatched_train!(
            io, model => device_m, training => training_state, data, init; callback
        )
    end

    bytes = read(seekstart(io))

    result = Result(;
        model,
        prefix = outputdir,
        uuid = uuid4(),
        iteration = best_N,
        stats = best_stats,
        trained = true,
        resumed = resume,
        successful = !isempty(bytes),
    )

    result.successful && write(get_path(result), bytes)

    return result 
end

function finalize_callback(
        io::IO, (model, device_m)::ModelPair, (training, training_state)::TrainingPair,
        valid_stream, (best_N, best_stats), (N, train_stats); callback
    )

    metrics = (model.loss, model.metrics...)
    valid_stats = compute_metrics(metrics, device_m, valid_stream)
    current_stats = (
        collect(Float64, train_stats),
        collect(Float64, valid_stats)
    )

    trace = Trace(stats = current_stats, metrics = collect(Any, metrics), iteration = N)
    callback(device_m, trace)

    valid_loss = first(current_stats[Int(DataPartition.validation)])
    best_valid_loss = first(best_stats[Int(DataPartition.validation)])

    if valid_loss < best_valid_loss
        truncate(io, 0)
        seekstart(io)
        state = StringDict("model_state" => Flux.cpu(Flux.state(device_m)))
        write_state(io, state)
        best_N, best_stats = N, current_stats
    end

    return any(Fix1(|>, valid_loss), training_state.stoppers), best_N => best_stats
end

function unbatched_train!(
        io::IO, (model, device_m)::ModelPair, (training, training_state)::TrainingPair,
        data::AbstractData{2}, (init_N, init_stats)::Pair; callback
    )

    # Turn model into a pair consisting of
    # - a flat vector of parameters `θ₀` and
    # - a function `re` to reconstruct the model from the parameters.
    θ₀, re = destructure(device_m)
    train_data = stream(only, data, DataPartition.training; batchsize = nothing, training.device)
    valid_data = stream(only, data, DataPartition.validation; batchsize = nothing, training.device)
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
            io::IO, model => re(θ), training => training_state, [valid_data],
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
        (training, training_state)::TrainingPair,
        train_stream
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
        io::IO, (model, device_m)::ModelPair, (training, training_state)::TrainingPair, data::AbstractData{2},
        (init_N, init_stats)::Pair; callback
    )

    rng = get_rng(training.seed)
    (; batchsize, device, shuffle) = training
    best = init_N => init_stats

    for epoch in 1:training.iterations
        N = epoch + init_N
        adjust_params!(training_state.optimizer, training.schedules, N)
        train_stats = stream(data, DataPartition.training; batchsize, device, rng, shuffle) do train_stream
            epoch_train!(model => device_m, training => training_state, train_stream)
        end
        current = N => train_stats
        stop, best = stream(data, DataPartition.validation; batchsize, device, shuffle = false) do valid_stream
            return finalize_callback(
                io::IO, model => device_m, training => training_state, valid_stream, best, current; callback
            )
        end
        stop && break
    end
    return best
end

function _train(
        model::Union{Model, Result}, training::Training, data::AbstractData{2};
        resume::Bool, callback = default_callback,
        outputdir, tempdir::AbstractString = Base.tempdir()
    )
    return mktemp(tempdir) do _, io
        return _train(io, model, training, data; resume, callback, outputdir)
    end
end

"""
    train(
        model::Model, training::Training, data::AbstractData{2};
        callback = default_callback, outputdir,
        tempdir::AbstractString = Base.tempdir()
    )

Train `model` using the `training` configuration on `data`.

The keyword arguments are as follows.

- `outputdir` represents the path where StreamlinerCore saves model weights (can be local or remote).
- `tempdir` represents a folder where StreamlinerCore will store temporary data during training.
- `callback(m, trace)` will be called after every epoch.

The arguments of `callback` work as follows.
- `m` is the instantiated neural network or machine,
- `trace` is an object encoding additional information, i.e.,
    - `stats` (average of metrics computed so far),
    - `metrics` (functions used to compute `stats`), and
    - `iteration`.
"""
function train(
        model::Model, training::Training, data::AbstractData{2};
        callback = default_callback, outputdir,
        tempdir::AbstractString = Base.tempdir()
    )
    return _train(model, training, data; callback, outputdir, tempdir, resume = false)
end

"""
    finetune(
        result::Result, training::Training, data::AbstractData{2};
        resume::Bool, callback = default_callback,
        outputdir, tempdir::AbstractString = Base.tempdir()
    )

Load model encoded in `result` and retrain it using the `training` configuration on `data`.
Use `resume = true` to restart training where it left off.
Same other keyword arguments as [`train`](@ref).
"""
function finetune(
        result::Result, training::Training, data::AbstractData{2};
        resume::Bool, callback = default_callback,
        outputdir, tempdir::AbstractString = Base.tempdir()
    )

    return _train(result, training, data; resume, callback, outputdir, tempdir)
end
