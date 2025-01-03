@testset "stream" begin
    train_x, train_y, test_x, test_y = get_mnist()
    # reproduce split from `setup.jl`
    train_idxs = filter(i -> mod(i, 3) != 0, 1:500)
    valid_idxs = filter(i -> mod(i, 3) == 0, 1:500)

    batchsize = 16
    d_train = Flux.DataLoader((train_x[:, :, :, train_idxs], train_y[:, train_idxs]); batchsize)
    d_valid = Flux.DataLoader((train_x[:, :, :, valid_idxs], train_y[:, valid_idxs]); batchsize)

    streaming = Streaming(; batchsize, device = cpu)

    StreamlinerCore.stream(train_regression_data, DataPartition.training, streaming) do train_stream
        for ((x1, y1), (x2, y2)) in zip(train_stream, d_train)
            @test x1 == x2
            @test size(y1) == size(y2)
        end

        @test length(train_stream) == length(d_train)
    end

    StreamlinerCore.stream(train_regression_data, DataPartition.validation, streaming) do valid_stream
        for ((x1, y1), (x2, y2)) in zip(valid_stream, d_valid)
            @test x1 == x2
            @test size(y1) == size(y2)
        end

        @test length(valid_stream) == length(d_valid)
    end
end
