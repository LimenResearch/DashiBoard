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
    x = rand(15, 20, 17, 3, 2)
    y = m(x)
    @test y == x[10:12, (end - 10):end, 1:3, :, :]
end

# TODO: individually test affine, byslice, and pooling layers
