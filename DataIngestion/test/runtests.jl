using DataIngestion
using IntervalSets, Dates
using DBInterface, DuckDBUtils, DataFrames, JSON3
using Test

@testset "load" begin
    repo = Repository()
    DBInterface.execute(Returns(nothing), repo, "CREATE SCHEMA csv")
    DBInterface.execute(Returns(nothing), repo, "CREATE SCHEMA json")
    DBInterface.execute(Returns(nothing), repo, "CREATE SCHEMA parquet")

    df1 = DataFrame(x = [1, 2, 3], y = ["a", "b", "c"])
    df2 = DataFrame(x = [4, 5, 6], y = ["d", "e", "f"])
    DuckDBUtils.load_table(repo, df1, "source1")
    DuckDBUtils.load_table(repo, df2, "source2")

    mktempdir() do dir
        path1 = joinpath(dir, "test1")
        path2 = joinpath(dir, "test2")

        DBInterface.execute(Returns(nothing), repo, "COPY (FROM source1) TO '$path1.csv'")
        DBInterface.execute(Returns(nothing), repo, "COPY (FROM source1) TO '$path1.json'")
        DBInterface.execute(Returns(nothing), repo, "COPY (FROM source1) TO '$path1.parquet'")

        DBInterface.execute(Returns(nothing), repo, "COPY (FROM source2) TO '$path2.csv'")
        DBInterface.execute(Returns(nothing), repo, "COPY (FROM source2) TO '$path2.json'")
        DBInterface.execute(Returns(nothing), repo, "COPY (FROM source2) TO '$path2.parquet'")

        DataIngestion.load_files(repo, ["$path1.csv"]; schema = "csv")
        df′ = DBInterface.execute(DataFrame, repo, "FROM csv.source")
        @test df′.x == [1, 2, 3]
        @test df′.y == ["a", "b", "c"]
        @test df′._name == ["test1", "test1", "test1"]

        DataIngestion.load_files(repo, ["$path1.csv", "$path2.csv"]; schema = "csv")
        df′ = DBInterface.execute(DataFrame, repo, "FROM csv.source")
        @test df′.x == [1, 2, 3, 4, 5, 6]
        @test df′.y == ["a", "b", "c", "d", "e", "f"]
        @test df′._name == ["test1", "test1", "test1", "test2", "test2", "test2"]


        DataIngestion.load_files(repo, ["$path1.json"]; schema = "json")
        df′ = DBInterface.execute(DataFrame, repo, "FROM json.source")
        @test df′.x == [1, 2, 3]
        @test df′.y == ["a", "b", "c"]
        @test df′._name == ["test1", "test1", "test1"]

        DataIngestion.load_files(repo, ["$path1.json", "$path2.json"]; schema = "json")
        df′ = DBInterface.execute(DataFrame, repo, "FROM json.source")
        @test df′.x == [1, 2, 3, 4, 5, 6]
        @test df′.y == ["a", "b", "c", "d", "e", "f"]
        @test df′._name == ["test1", "test1", "test1", "test2", "test2", "test2"]

        DataIngestion.load_files(repo, ["$path1.parquet"]; schema = "parquet")
        df′ = DBInterface.execute(DataFrame, repo, "FROM parquet.source")
        @test df′.x == [1, 2, 3]
        @test df′.y == ["a", "b", "c"]
        @test df′._name == ["test1", "test1", "test1"]

        DataIngestion.load_files(repo, ["$path1.parquet", "$path2.parquet"]; schema = "parquet")
        df′ = DBInterface.execute(DataFrame, repo, "FROM parquet.source")
        @test df′.x == [1, 2, 3, 4, 5, 6]
        @test df′.y == ["a", "b", "c", "d", "e", "f"]
        @test df′._name == ["test1", "test1", "test1", "test2", "test2", "test2"]
    end
end

@testset "filtering" begin
    repo = Repository()
    schema = "schm"
    DBInterface.execute(Returns(nothing), repo, "CREATE SCHEMA schm")
    spec = open(JSON3.read, joinpath(@__DIR__, "static", "data.json"))
    DataIngestion.load_files(repo, spec["files"]; schema)

    f1 = DataIngestion.IntervalFilter(
        "hour",
        1 .. 3
    )

    f2 = DataIngestion.ListFilter(
        "cbwd",
        ["NW", "SE"]
    )

    filters = [f1, f2]

    DataIngestion.select(repo, filters; schema)

    df = DBInterface.execute(DataFrame, repo, "FROM schm.selection")
    @test unique(sort(df.cbwd)) == ["NW", "SE"]
    @test unique(sort(df.hour)) == [1, 2, 3]
end

@testset "dates" begin
    repo = Repository()
    schema = "schm"
    DBInterface.execute(Returns(nothing), repo, "CREATE SCHEMA schm")
    path = joinpath(@__DIR__, "static", "dates.csv")
    DataIngestion.load_files(repo, [path], dateformat = "%m/%d/%Y"; schema)
    f = IntervalFilter("date", Date(2023, 12, 09) .. Date(2023, 12, 10))
    DataIngestion.select(repo, [f]; schema)
    df = DBInterface.execute(DataFrame, repo, "FROM schm.selection")
    df′ = DataFrame(
        row = [1, 2],
        date = [Date(2023, 12, 09), Date(2023, 12, 10)],
        time = [Time(15, 25, 0), Time(14, 22, 0)]
    )
    @test df.row == df′.row
    @test df.date == df′.date
    @test df.time == df′.time
end

@testset "from json" begin
    d = open(JSON3.read, joinpath(@__DIR__, "static", "filters.json"))
    filters = DataIngestion.get_filter.(d)

    @test length(filters) == 2
    @test filters[1] isa DataIngestion.IntervalFilter
    @test filters[1].colname == "year"
    @test filters[1].interval == 2011 .. 2012

    @test filters[2] isa DataIngestion.ListFilter
    @test filters[2].colname == "cbwd"
    @test filters[2].list == ["NW", "SW"]
end

@testset "summary" begin
    repo = Repository()
    schema = "schm"
    DBInterface.execute(Returns(nothing), repo, "CREATE SCHEMA schm")
    spec = open(JSON3.read, joinpath(@__DIR__, "static", "data.json"))
    DataIngestion.load_files(repo, spec["files"]; schema)
    info = DataIngestion.summarize(repo, "source"; schema)
    df = DBInterface.execute(DataFrame, repo, "FROM schm.source")
    @test [x.name for x in info] == names(df)

    No_min, No_max = extrema(df.No)
    @test info[1].name == "No"
    @test info[1].type == "numerical"
    @test info[1].summary == (
        min = No_min,
        max = No_max,
        step = round((No_max - No_min) / 100, sigdigits = 2),
    )

    @test info[10].name == "cbwd"
    @test info[10].type == "categorical"
    @test info[10].summary == unique(sort(df.cbwd))
end
