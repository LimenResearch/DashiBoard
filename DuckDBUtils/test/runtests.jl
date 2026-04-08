using DuckDB, DuckDBUtils, DBInterface, Tables
using FunSQL: From, Where, Get, Var
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
    res = DuckDBUtils.replace_table(r, From("tbl"), "tbl2"; schema = "schm")
    @test res == (; Count = 3)
    tbl = DBInterface.execute(Tables.columntable, r, "FROM schm.tbl2;")
    @test tbl.a == x.a
    @test tbl.b == x.b

    DuckDBUtils.delete_table(r, "tbl"; schema = "schm")
    @test_throws DuckDB.QueryException DBInterface.execute(Tables.columntable, r, "FROM schm.tbl;")
end

@testset "table export" begin
    r = Repository()
    DBInterface.execute(Returns(nothing), r, "CREATE SCHEMA IF NOT EXISTS \"schm\";")

    mktempdir() do dir
        path1 = joinpath(dir, "table1.csv")
        path2 = joinpath(dir, "table2.csv")
        x = (x = 1:3, y = ["a", "b", "c"])
        DuckDBUtils.with_table(r, x; schema = "schm") do name
            res1 = DuckDBUtils.export_table(r, From(name), path1; schema = "schm")
            res2 = DuckDBUtils.export_table(r, "FROM \"schm\".\"$(name)\"", path2)
            @test res1 == (; Count = 3)
            @test res2 == (; Count = 3)
            read(path1, String) == "x,y\n1,a\n2,b\n3,c\n"
            read(path2, String) == "x,y\n1,a\n2,b\n3,c\n"
            @test_warn "Schema will be ignored" DuckDBUtils.export_table(r, "FROM \"schm\".\"$(name)\"", path2; schema = "schm")
        end
    end
end

# TODO: test Batches
