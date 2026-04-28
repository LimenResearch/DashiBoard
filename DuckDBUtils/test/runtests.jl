using DuckDB, DuckDBUtils, DBInterface, Tables
using FunSQL: From, Where, Get, Var
using OrderedCollections: OrderedDict
using Test

@testset "show" begin
    r = Repository()
    s = sprint(show, r)
    @test sprint(show, r) == "Repository(DuckDB.DB(\":memory:\"), Connections(limit = 4096))"
    @test sprint(show, r.connections) == "Connections(limit = 4096)"

    r = Repository(limit = 100)
    @test sprint(show, r) == "Repository(DuckDB.DB(\":memory:\"), Connections(limit = 100))"

    mktempdir() do dir
        path = joinpath(dir, "test_db.duckdb")
        r = Repository(path, limit = 100)
        @test sprint(show, r) == "Repository(DuckDB.DB(\"$(path)\"), Connections(limit = 100))"
    end
end

@testset "connections" begin
    r = Repository()
    con1 = acquire_connection(r)
    @test con1 isa DuckDB.Connection
    release_connection(r, con1)
    con2 = acquire_connection(r)
    @test con2 === con1
    release_connection(r, con2)
    drain_connections!(r)
    con3 = acquire_connection(r)
    @test con3 !== con1
    release_connection(r, con3)
    with_connection(r) do con
        @test con === con3
    end
    con4 = acquire_connection(r)
    @test con4 === con3
    release_connection(r, con4)
end

@testset "multidict" begin
    s = Set([1, 3, 4, 7])
    idxs = DuckDBUtils.first_not_in!(s, 5)
    @test idxs == [2, 5, 6, 8, 9]
    @test issetequal(s, 1:9)
    s = Set([1, 3, 4, 7])
    idxs = DuckDBUtils.first_not_in!(s, 2)
    @test idxs == [2, 5]
    @test issetequal(s, [1, 2, 3, 4, 5, 7])
    s = Set([1, 3, 4, 7])
    @test_throws ArgumentError DuckDBUtils.first_not_in!(s, 4095)
end

@testset "utils" begin
    r = Repository()
    n = DBInterface.execute(
        DuckDBUtils.to_nrow,
        r,
        """
        CREATE TABLE t1 AS (SELECT 1 AS x, 2 AS j);
        """
    )
    @test n == 1

    res = DBInterface.execute(
        DuckDBUtils.table_creation_summary,
        r,
        """
        CREATE TABLE t2 AS (SELECT 1 AS x, 2 AS j);
        """
    )
    @test res == (; Count = 1)
end

# TODO: test initialize_table
@testset "load and delete tables" begin
    r = Repository()
    DBInterface.execute(Returns(nothing), r, "CREATE SCHEMA IF NOT EXISTS \"schm\";")

    x = (a = 1:3, b = ["a", "b", "c"])
    res = DuckDBUtils.load_table(r, x, "tbl"; schema = "schm")
    @test res == (; Count = 3)
    @test DuckDBUtils.colnames(r, "tbl"; schema = "schm") == ["a", "b"]

    tbl = DBInterface.execute(Tables.columntable, r, "FROM schm.tbl;")
    @test tbl.a == x.a
    @test tbl.b == x.b
    nm = DuckDBUtils.in_schema("tbl", "schm")
    tbl2 = DBInterface.execute(Tables.columntable, r, "FROM $(nm);")
    @test tbl2.a == x.a
    @test tbl2.b == x.b
    tbl3 = DBInterface.execute(Tables.columntable, r, From("tbl"); schema = "schm")
    @test tbl2.a == x.a
    @test tbl2.b == x.b

    tbl4 = DBInterface.execute(
        Tables.columntable,
        r,
        From("tbl") |> Where(Get.a .== Var.val),
        (val = 2,); schema = "schm"
    )
    @test tbl4.a == [2]
    @test tbl4.b == ["b"]

    @test_throws ArgumentError DuckDBUtils.replace_table(r, From("tbl"), [], "tbl2"; schema = "schm")

    res = DuckDBUtils.replace_table(r, From("tbl"), "tbl2"; schema = "schm", virtual = true)
    @test isnothing(res)
    tbl = DBInterface.execute(Tables.columntable, r, "FROM schm.tbl2;")
    @test tbl.a == x.a
    @test tbl.b == x.b
    DuckDBUtils.delete_table(r, "tbl2"; schema = "schm", virtual = true)

    mktempdir() do data_dir
        db_path = joinpath(data_dir, "db.duckdb")
        DBInterface.execute(Returns(nothing), r, "ATTACH '$(db_path)' AS my_db;")
        DBInterface.execute(Returns(nothing), r, "CREATE TABLE my_db.main.tbl(i BIGINT, j BIGINT);")
        res3 = DuckDBUtils.replace_table(r, "FROM my_db.tbl", "external_view"; schema = "schm")
        @test isnothing(res)
        tbl = DBInterface.execute(Tables.columntable, r, "FROM schm.external_view;")
        @test tbl.i == Int64[]
        @test tbl.j == Int64[]
    end

    res = DuckDBUtils.replace_table(r, From("tbl"), "tbl2"; schema = "schm")
    @test res == (; Count = 3)
    tbl = DBInterface.execute(Tables.columntable, r, "FROM schm.tbl2;")
    @test tbl.a == x.a
    @test tbl.b == x.b

    DuckDBUtils.delete_table(r, "tbl"; schema = "schm")
    @test_throws DuckDB.QueryException DBInterface.execute(Tables.columntable, r, "FROM schm.tbl;")

    DuckDBUtils.query(Returns(nothing), r, "CREATE SCHEMA schm2; CREATE TABLE schm2.tbl(i BIGINT);")
    ns = DBInterface.execute(res -> map(row -> row.name, res), r, "SHOW TABLES FROM schm2")
    @test ns == ["tbl"]
    @test_throws DuckDB.QueryException DuckDBUtils.transaction(r, "CREATE TABLE schm2.tbl;")
    DuckDBUtils.transaction(r, "CREATE TABLE schm2.tbl2(i BIGINT); CREATE TABLE schm2.tbl3(i BIGINT);")
    ns = DBInterface.execute(res -> map(row -> row.name, res), r, "SHOW TABLES FROM schm2")
    @test issetequal(ns, ["tbl", "tbl2", "tbl3"])
end

@testset "table export" begin
    r = Repository()
    DBInterface.execute(Returns(nothing), r, "CREATE SCHEMA IF NOT EXISTS \"schm\";")

    mktempdir() do dir
        path1 = joinpath(dir, "table1.csv")
        path2 = joinpath(dir, "table2.csv")
        path3 = joinpath(dir, "table3.csv")
        x = (x = 1:3, y = ["a", "b", "c"])
        DuckDBUtils.with_table(r, x; schema = "schm") do name
            res1 = DuckDBUtils.export_table(r, From(name), path1; schema = "schm")
            res2 = DuckDBUtils.export_table(r, "FROM \"schm\".\"$(name)\"", path2)
            @test res1 == (; Count = 3)
            @test res2 == (; Count = 3)
            @test read(path1, String) == "x,y\n1,a\n2,b\n3,c\n"
            @test read(path2, String) == "x,y\n1,a\n2,b\n3,c\n"
            @test_warn "Schema will be ignored" DuckDBUtils.export_table(r, "FROM \"schm\".\"$(name)\"", path2; schema = "schm")
        end
        mktempdir() do data_dir
            db_path = joinpath(data_dir, "db.duckdb")
            DBInterface.execute(Returns(nothing), r, "ATTACH '$(db_path)' AS my_db;")
            DBInterface.execute(Returns(nothing), r, "CREATE TABLE my_db.main.tbl(i BIGINT, j BIGINT);")
            res3 = DuckDBUtils.export_table(r, "FROM my_db.tbl", path3)
            @test res3 == (; Count = 0)
            @test read(path3, String) == "i,j\n"
        end
    end
end

@testset "batches" begin
    r = Repository()
    nrows = 1000
    batchsize = 32
    tbl = (x = rand(Int, nrows), y = rand(nrows))
    DuckDBUtils.load_table(r, tbl, "tbl")
    with_connection(r) do con
        result = DBInterface.execute(con, "FROM tbl", DuckDB.StreamResult)
        batches = Batches(result, batchsize, nrows)
        ps = Iterators.partition(1:nrows, batchsize)
        N = length(ps)
        @test length(batches) == N
        @test size(batches) == (N,)
        l = Any[]
        for (batch, idxs) in zip(batches, ps)
            @test batch[:x] == tbl.x[idxs]
            @test batch[:y] == tbl.y[idxs]
            push!(l, batch)
        end
        @test length(l) == N
        @test eltype(batches) == OrderedDict{Symbol, Vector}
        s = sprint(show, batches)
        T = typeof(Tables.partitions(result))
        expected = """
        Batches{$(T), (:x, :y), Tuple{Union{Missing, Int64}, Union{Missing, Float64}}}(batchsize = 32, nrows = 1000)
        """
        @test s == chomp(expected)
        DBInterface.close!(result)
    end
end
