@testset "spatial format" begin
    fmt0 = StreamlinerCore.FlatFormat()
    fmt1 = StreamlinerCore.SpatialFormat{1}()
    fmt2 = StreamlinerCore.SpatialFormat{2}()
    @test_throws MethodError StreamlinerCore.instantiate(
        StreamlinerCore.Reshaper(),
        fmt2,
        (1, 2, 3),
        outputformat = fmt1
    )

    x = rand(110, 16)
    @test StreamlinerCore.unflatten(x, (2, 5, 11)) == reshape(x, 2, 5, 11, 16)

    @test StreamlinerCore.instantiate(
        StreamlinerCore.Reshaper(), (110,), fmt0, outputformat = fmt2
    ) === (
        Base.Fix2(StreamlinerCore.unflatten, (2, 5, 11)),
        (2, 5, 11),
        fmt2,
    )

    @test StreamlinerCore.instantiate(
        StreamlinerCore.Reshaper(), (2, 5, 11), fmt2, outputformat = fmt0
    ) === (
        MLUtils.flatten,
        (110,),
        fmt0,
    )
end
