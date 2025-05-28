using StreamlinerCore
using StreamlinerCore: formatter, Shape
using Flux
using Flux: onehotbatch
using MLUtils
using MLUtils: flatten, numobs, getobs, DataLoader
using Optimisers: Adam
using ParameterSchedulers: CosAnneal
using MLDatasets: MNIST
using MLDataDevices: CPUDevice
using JLD2
using ChainRulesTestUtils
using Test, Random

# Get MNIST dataset

ENV["DATADEPS_ALWAYS_ACCEPT"] = true

static_dir = joinpath(@__DIR__, "static")
parser = default_parser()

function get_mnist()
    train_x, train_y = MNIST(split = :train)[:]
    test_x, test_y = MNIST(split = :test)[:]
    train_x = reshape(train_x, 28, 28, 1, :)
    test_x = reshape(test_x, 28, 28, 1, :)
    train_y = Flux.onehotbatch(train_y, 0:9)
    test_y = Flux.onehotbatch(test_y, 0:9)
    return train_x, train_y, test_x, test_y
end

batches(d, batchsize; device, shuffle) = Iterators.map(device, DataLoader(d; batchsize, shuffle))
batches(d, ::Nothing; device, shuffle) = [device(d)]

# Define streamer of MNIST data (just a small fraction for demonstration purposes)

train_idxs = filter(i -> mod(i, 3) != 0, 1:500)
valid_idxs = filter(i -> mod(i, 3) == 0, 1:500)
test_idxs = 1:100

train_x, train_y, test_x, test_y = get_mnist()

regression_train_data = (input = train_x, target = train_y)
regression_test_data = (input = test_x, target = test_y)

hybrid_train_data = (input = train_x, metadata = train_x, target = train_y)
hybrid_test_data = (input = test_x, metadata = test_x, target = test_y)

autoencoder_train_data = (input = train_x,)
autoencoder_test_data = (input = test_x,)

prediction_train_data = (input = train_x, target = train_x[12:17, 14:14, :, :])
prediction_test_data = (input = test_x, target = test_x[12:17, 14:14, :, :])

## Prepare to stream data

using StreamlinerCore: Template, Data

table = "mnist"

regression_templates = (
    input = Template(Float32, (28, 28, 1)),
    target = Template(Bool, (10,)),
)
regression_metadata = Dict("id" => "regression-mnist")
train_regression_data = Data{2}(
    (
        getobs(regression_train_data, train_idxs),
        getobs(regression_train_data, valid_idxs),
    ),
    regression_templates,
    regression_metadata
)
test_regression_data = Data{1}(
    (getobs(regression_test_data, test_idxs),),
    regression_templates,
    regression_metadata
)

hybrid_templates = (
    input = Template(Float32, (28, 28, 1)),
    metadata = Template(Float32, (3,)),
    target = Template(Bool, (10,)),
)
hybrid_metadata = Dict("id" => "hybrid-mnist")
train_hybrid_data = Data{2}(
    (
        getobs(hybrid_train_data, train_idxs),
        getobs(hybrid_train_data, valid_idxs),
    ),
    hybrid_templates,
    hybrid_metadata
)
test_hybrid_data = Data{1}(
    (getobs(hybrid_test_data, test_idxs),),
    hybrid_templates,
    hybrid_metadata
)

autoencoder_templates = (
    input = Template(Float32, (28, 28, 1)),
)
autoencoder_metadata = Dict("id" => "autoencoder-mnist")
train_autoencoder_data = Data{2}(
    (
        getobs(autoencoder_train_data, train_idxs),
        getobs(autoencoder_train_data, valid_idxs),
    ),
    autoencoder_templates,
    autoencoder_metadata
)
test_autoencoder_data = Data{1}(
    (getobs(autoencoder_test_data, test_idxs),),
    autoencoder_templates,
    autoencoder_metadata
)

prediction_templates = (
    input = Template(Float32, (28, 28, 1)),
    target = Template(Float32, (6, 1, 1)),
)
prediction_metadata = Dict("id" => "prediction-mnist")
train_prediction_data = Data{2}(
    (
        getobs(prediction_train_data, train_idxs),
        getobs(prediction_train_data, valid_idxs),
    ),
    prediction_templates,
    prediction_metadata
)
test_prediction_data = Data{1}(
    (getobs(prediction_test_data, test_idxs),),
    prediction_templates,
    prediction_metadata
)

@info "Regression data summary statistics"

streaming = Streaming(batchsize = 32, device = CPUDevice())

StreamlinerCore.stream(train_regression_data, DataPartition.training, streaming) do train_stream
    @show length(train_stream)
    @show map(size, first(train_stream))
    return
end

@info "Autoencoder data summary statistics"

StreamlinerCore.stream(train_autoencoder_data, DataPartition.training, streaming) do train_stream
    @show length(train_stream)
    @show map(size, first(train_stream))
    return
end
