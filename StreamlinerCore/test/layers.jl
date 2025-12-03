@testset "dense" begin
    c = Dict(
        "name" => "dense",
        "features" => 3,
        "sigma" => "tanh",
    )
    l = StreamlinerCore.parse_layer(c)
    @test l.features == 3
    @test l.sigma == tanh
    @test StreamlinerCore.requires_shape(l) == Shape(StreamlinerCore.FlatFormat())

    input_shape = Shape((), 7)
    output_shape = Shape(StreamlinerCore.FlatFormat())
    m, sh = StreamlinerCore.instantiate(l, input_shape, output_shape)
    @test m isa Flux.Dense
    @test sh == Shape((), 3)
    @test size(m.weight) == (3, 7)
    x = rand(Float32, 7, 2)
    y = m(x)
    @test y ≈ tanh.(m.weight * x .+ m.bias)
end

@testset "conv" begin
    c = Dict(
        "name" => "conv",
        "features" => 3,
        "sigma" => "tanh",
        "kernel" => [2, 2],
    )
    l = StreamlinerCore.parse_layer(c)
    @test l.features == 3
    @test l.sigma == tanh
    @test l.kernel == (2, 2)
    @test StreamlinerCore.requires_shape(l) == Shape(StreamlinerCore.SpatialFormat{2}())

    input_shape = Shape((5, 5), 7)
    output_shape = Shape(StreamlinerCore.SpatialFormat{2}())
    m, sh = StreamlinerCore.instantiate(l, input_shape, output_shape)
    @test m isa Flux.Conv
    @test sh == Shape((4, 4), 3)
    @test size(m.weight) == (2, 2, 7, 3)
    x = rand(Float32, 5, 5, 7, 2)
    y = m(x)
    @test y ≈ tanh.(Flux.conv(x, m.weight) .+ reshape(m.bias, 1, 1, :))
end

@testset "byslice" begin
    c = Dict(
        "name" => "softmax",
        "dims" => 1,
    )
    l = StreamlinerCore.parse_layer(c)
    @test StreamlinerCore.requires_shape(l) == Shape(StreamlinerCore.FlatFormat())
    input_shape = Shape((), 7)
    output_shape = Shape(StreamlinerCore.FlatFormat())
    m, sh = StreamlinerCore.instantiate(l, input_shape, output_shape)
    @test m === l
    @test sh == Shape((), 7)
    x = rand(Float32, 7, 2)
    y = m(x)
    @test y ≈ Flux.softmax(x, dims = 1)
end

@testset "pooling" begin
    c = Dict(
        "name" => "maxpool",
        "window" => [2, 2],
    )
    l = StreamlinerCore.parse_layer(c)
    @test l.window == (2, 2)
    @test StreamlinerCore.requires_shape(l) == Shape(StreamlinerCore.SpatialFormat{2}())

    input_shape = Shape((6, 6), 5)
    output_shape = Shape(StreamlinerCore.SpatialFormat{2}())
    m, sh = StreamlinerCore.instantiate(l, input_shape, output_shape)
    @test m isa Flux.MaxPool
    @test sh == Shape((3, 3), 5)
    x = rand(Float32, 6, 6, 5, 2)
    y = m(x)
    @test y ≈ Flux.MaxPool((2, 2))(x)
end

@testset "upsampling" begin
    c = Dict(
        "name" => "upsample",
        "size" => [5, 7],
    )
    l = StreamlinerCore.parse_layer(c)
    @test l.size == (5, 7)
    @test StreamlinerCore.requires_shape(l) == Shape(StreamlinerCore.SpatialFormat{2}())

    input_shape = Shape((3, 3), 5)
    output_shape = Shape(StreamlinerCore.SpatialFormat{2}())
    m, sh = StreamlinerCore.instantiate(l, input_shape, output_shape)
    @test m === l
    @test sh == Shape((5, 7), 5)
    x = rand(Float32, 3, 3, 5, 2)
    y = m(x)
    @test y ≈ Flux.upsample_linear(x; size = (5, 7), align_corners = false)
end

@testset "selector" begin
    c = Dict(
        "name" => "selector",
        "window" => [
            Dict("min" => 10, "max" => 12),
            Dict("last" => 11),
            Dict("first" => 3),
        ]
    )
    l = StreamlinerCore.parse_layer(c)
    @test l.window == (
        StreamlinerCore.range_selector(min = 10, max = 12),
        StreamlinerCore.range_selector(last = 11),
        StreamlinerCore.range_selector(first = 3),
    )
    @test StreamlinerCore.requires_shape(l) == Shape(StreamlinerCore.SpatialFormat{3}())

    input_shape = Shape((15, 20, 17), 3)
    output_shape = Shape(StreamlinerCore.SpatialFormat{3}())
    m, sh = StreamlinerCore.instantiate(l, input_shape, output_shape)
    @test m === l
    x = rand(15, 20, 17, 3, 2)
    y = m(x)
    @test y == x[10:12, (end - 10):end, 1:3, :, :]
    @test sh == Shape((3, 11, 3), 3)
end
