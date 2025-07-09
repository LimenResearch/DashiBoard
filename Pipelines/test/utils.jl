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

@testset "counting_sortperm" begin
    ps = [2, 2, 1, 0, 11, 1, -1]
    @test Pipelines.counting_sortperm(ps) == [7, 4, 3, 6, 1, 2, 5]
    @test Pipelines.counting_sortperm([]) == Int[]
end
