using DataIngestion
using IntervalSets, Dates
using DBInterface, DuckDBUtils, DataFrames, JSON3
using Test

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
