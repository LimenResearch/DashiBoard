@testset "name manipulations" begin
    col = "temp"
    suffix = "hat"
    i = 3
    @test Pipelines.join_names(col, suffix, i) == "temp_hat_3"
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
    d1 = Pipelines.apply_helpers(hs, d, ps; recursive = 0)
    @test issetequal(keys(d1), ["a", "b", "c"])
    @test d1["a"] == [12.3, 12, "varname_1", "varname_2", "varname_3", "varname_4", "varname_5"]
    @test d1["b"] == Dict("c" => "abc")
    @test d1["c"] == [1, 2, 3, 4, 5, 6]

    d = Dict("a" => Dict("-v" => "var"))
    ps = Dict("var" => Dict("-v" => "var"))
    d1 = Pipelines.apply_helpers(hs, d, ps; recursive = 0)
    @test d1 == d

    d = Dict("a" => Dict("-v" => "var1"))
    ps = Dict("var1" => Dict("-v" => "var2"), "var2" => 10)
    d1 = Pipelines.apply_helpers(hs, d, ps; recursive = 0)
    @test d1 == Dict("a" => Dict("-v" => "var2"))

    d = Dict("a" => Dict("-v" => "var1"))
    ps = Dict("var1" => Dict("-v" => "var2"), "var2" => 10)
    d1 = Pipelines.apply_helpers(hs, d, ps, recursive = 1)
    @test d1 == Dict("a" => 10)

    d = Dict("a" => [Dict("-s" => "var1"), 12])
    ps = Dict("var1" => [Dict("-v" => "var2"), 11], "var2" => 10)
    d1 = Pipelines.apply_helpers(hs, d, ps, recursive = 1)
    @test d1 == Dict("a" => [10, 11, 12])

    d = Dict("a" => Dict("-s" => "var"))
    ps = Dict("var" => [1, 2, 3])
    d1 = Pipelines.apply_helpers(hs, d, ps, recursive = 0)
    @test d1 == Dict("a" => [1, 2, 3])
end

@testset "join_on_id_var" begin
    r = Repository()
    tbl1 = (x = 1:10, y = rand(10))
    tbl2 = (x = 1:10, z = rand(10), w = rand(10))
    DBInterface.execute(Returns(nothing), r, "CREATE SCHEMA schm;")
    DuckDBUtils.load_table(r, tbl1, "tbl1"; schema = "schm")
    DuckDBUtils.load_table(r, tbl2, "tbl2"; schema = "schm")
    Pipelines.join_on_id_var(r, "tbl1", "tbl2", "x", ["z", "w"]; schema = "schm")
    df = DBInterface.execute(DataFrame, r, From("tbl1") |> Order(Get.x); schema = "schm")
    @test names(df) == ["x", "y", "z", "w"]
    @test df.x == 1:10
    @test df.y == tbl1.y
    @test df.z == tbl2.z
    @test df.w == tbl2.w
end

@testset "fromtable" begin
    tbl1 = [(x = rand(), y = rand(), z = "a") for _ in 1:10]
    tbl2 = DataFrame(tbl1)
    d1 = Pipelines.fromtable(tbl1)
    d2 = Pipelines.fromtable(tbl2)
    @test d1 == d2
    @test collect(keys(d1)) == ["x", "y", "z"]
    @test d1["x"] == tbl2.x
    @test d1["y"] == tbl2.y
    @test d1["z"] == tbl2.z
end
