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

@testset "vars" begin
    vars = ["a", "a", "b", "c", "d", "c"]
    @test issetequal(Pipelines.repeated_values(vars), ["a", "c"])
    @test isempty(Pipelines.repeated_values(["a", "b", ""]))
end

@testset "array tools" begin
    v = [1, 2, 4]
    w = Pipelines.circ_prepend(v, 5)
    @test w == [5, 1, 2]
    w = Pipelines.circ_append(v, 7)
    @test w == [2, 4, 7]
end
