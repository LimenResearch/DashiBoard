@testset "utils" begin
    col = "temp"
    suffix = "hat"
    i = 3
    @test Pipelines.join_names(col, suffix, i) == "temp_hat_3"
    c = Pipelines.new_name("a", ["a_1", "b", "a_3"])
    @test c == "a_2"
    c = Pipelines.new_name("a", ["b"])
    @test c == "a_1"

    @test Pipelines.to_string_dict((a = 1, b = 2)) == Dict("a" => 1, "b" => 2)
    @test Pipelines.to_string_dict(1 + 2im) == Dict("re" => 1, "im" => 2)

    @test Pipelines.to_symbol_dict(Dict("a" => 1, "b" => 2)) == Dict(:a => 1, :b => 2)
end
