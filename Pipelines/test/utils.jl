@testset "colnames" begin
    col = "temp"
    suffix = "hat"
    i = 3
    @test Pipelines.join_names(col, suffix, i) == "temp_hat_3"
    c = Pipelines.new_name("a", ["a_1", "b", "a_3"])
    @test c == "a_2"
    c = Pipelines.new_name("a", ["b"])
    @test c == "a_1"
end

@testset "array utils" begin
    v = [0, 0, 1, 2, 2, 4, 5, 5]
    b, e = Pipelines.borders(v)
    @test b == Bool[1, 0, 1, 1, 0, 1, 1, 0]
    @test e == Bool[0, 1, 1, 0, 1, 1, 0, 1]
    vars = ["a", "a", "b", "c", "d", "c"]
    @test issetequal(Pipelines.repeated_values(vars), ["a", "c"])
    @test isempty(Pipelines.repeated_values(["a", "b", ""]))
end
