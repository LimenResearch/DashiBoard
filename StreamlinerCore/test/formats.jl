@testset "spatial format" begin
    fmt0 = StreamlinerCore.FlatFormat()
    fmt1 = StreamlinerCore.SpatialFormat{1}()
    fmt2 = StreamlinerCore.SpatialFormat{2}()
    @test StreamlinerCore.instantiate(StreamlinerCore.Reshaper(fmt0), (5,), fmt0) === (nothing, (5,), fmt0)
    @test StreamlinerCore.instantiate(StreamlinerCore.Reshaper(fmt1), (1, 2), fmt1) === (nothing, (1, 2), fmt1)
    @test_throws MethodError StreamlinerCore.instantiate(StreamlinerCore.Reshaper(fmt1), (1, 2, 3), fmt2)

    x = rand(110, 16)
    @test StreamlinerCore.unflatten(x, (2, 5, 11)) == reshape(x, 2, 5, 11, 16)

    @test StreamlinerCore.instantiate(StreamlinerCore.Reshaper(fmt2), (110,), fmt0) === (
        Base.Fix2(StreamlinerCore.unflatten, (2, 5, 11)),
        (2, 5, 11),
        fmt2,
    )

    @test StreamlinerCore.instantiate(StreamlinerCore.Reshaper(fmt0), (2, 5, 11), fmt2) === (
        MLUtils.flatten,
        (110,),
        fmt0,
    )
end
