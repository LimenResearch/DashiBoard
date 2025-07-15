@testset "name manipulations" begin
    col = "temp"
    suffix = "hat"
    i = 3
    @test Pipelines.join_names(col, suffix, i) == "temp_hat_3"
    c = Pipelines.new_name("a", ["a_1", "b", "a_3"])
    @test c == "a_2"
    c = Pipelines.new_name("a", ["b"])
    @test c == "a_1"
    c = Pipelines.new_name("a", ["a_1", "a_2"], ["a_3"])
    @test c == "a_4"
end
