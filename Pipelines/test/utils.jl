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

@testset "dict_helpers" begin
    hs = [
        Pipelines.VariableHelper(),
        Pipelines.SpliceHelper(),
        Pipelines.RangeHelper(),
        Pipelines.JoinHelper(),
    ]
    d = Dict(
        "a" => [Dict("-v" => "num"), 12, Dict("-j" => ["varname", Dict("-r" => 5)])],
        "b" => Dict("c" => Dict("-v" => "str")),
        "c" => [Dict("-s" => "list"), 4, 5, 6]
    )
    ps = Dict("num" => 12.3, "list" => [1, 2, 3], "str" => "abc")
    d1 = Pipelines.apply_helpers(hs, d, ps)
    @test issetequal(keys(d1), ["a", "b", "c"])
    @test d1["a"] == [12.3, 12, "varname_1", "varname_2", "varname_3", "varname_4", "varname_5"]
    @test d1["b"] == Dict("c" => "abc")
    @test d1["c"] == [1, 2, 3, 4, 5, 6]

    d = Dict("a" => Dict("-v" => "var"))
    ps = Dict("var" => Dict("-v" => "var"))
    d1 = Pipelines.apply_helpers(hs, d, ps)
    @test d1 == d

    d = Dict("a" => Dict("-v" => "var1"))
    ps = Dict("var1" => Dict("-v" => "var2"), "var2" => 10)
    d1 = Pipelines.apply_helpers(hs, d, ps)
    @test d1 == Dict("a" => Dict("-v" => "var2"))

    d = Dict("a" => Dict("-v" => "var1"))
    ps = Dict("var1" => Dict("-v" => "var2"), "var2" => 10)
    d1 = Pipelines.apply_helpers(hs, d, ps, max_rec = 1)
    @test d1 == Dict("a" => 10)

    d = Dict("a" => [Dict("-s" => "var1"), 12])
    ps = Dict("var1" => [Dict("-v" => "var2"), 11], "var2" => 10)
    d1 = Pipelines.apply_helpers(hs, d, ps, max_rec = 1)
    @test d1 == Dict("a" => [10, 11, 12])
end
