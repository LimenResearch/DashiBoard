@testset "spatial format" begin
    fmt0 = StreamlinerCore.FlatFormat()
    fmt1 = StreamlinerCore.SpatialFormat{1}()
    fmt2 = StreamlinerCore.SpatialFormat{2}()
    @test Shape(5).format === fmt0
    @test Shape(1, (2,)).format === fmt1
    @test Shape(1, (2, 3)).format === fmt2

    @test StreamlinerCore.instantiate(formatter, Shape(5), Shape(5)) === (nothing, Shape(5))
    @test StreamlinerCore.instantiate(formatter, Shape(1, (2,)), Shape(1, (2,))) === (nothing, Shape(1, (2,)))
    @test_throws MethodError StreamlinerCore.instantiate(
        formatter,
        Shape(1, (2,)),
        Shape(1, (2, 3))
    )

    x = rand(110, 16)
    @test StreamlinerCore.unflatten(x, Shape(11, (2, 5))) == reshape(x, 2, 5, 11, 16)

    @test StreamlinerCore.instantiate(formatter, Shape(110), Shape(fmt2)) === (
        Base.Fix2(StreamlinerCore.unflatten, Shape(11, (2, 5))),
        Shape(11, (2, 5))
    )

    @test StreamlinerCore.instantiate(formatter, Shape(2, (5, 11)), Shape(fmt0)) === (
        MLUtils.flatten,
        Shape(110)
    )
end
