@testset "spatial format" begin
    fmt0 = StreamlinerCore.FlatFormat()
    fmt1 = StreamlinerCore.SpatialFormat{1}()
    fmt2 = StreamlinerCore.SpatialFormat{2}()
    @test Shape(5).format === fmt0
    @test Shape((1,), 2).format === fmt1
    @test Shape((1, 2), 3).format === fmt2

    @test_throws MethodError StreamlinerCore.instantiate(
        formatter,
        Shape((1,), 2),
        Shape((1, 2), 3)
    )

    x = rand(110, 16)
    @test StreamlinerCore.unflatten(x, Shape((2, 5), 11)) == reshape(x, 2, 5, 11, 16)

    @test StreamlinerCore.instantiate(formatter, Shape(110), Shape(fmt2)) === (
        Base.Fix2(StreamlinerCore.unflatten, Shape((2, 5), 11)),
        Shape((2, 5), 11)
    )

    @test StreamlinerCore.instantiate(formatter, Shape((2, 5), 11), Shape(fmt0)) === (
        MLUtils.flatten,
        Shape(110)
    )
end
