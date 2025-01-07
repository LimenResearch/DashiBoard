using DataIngestion
using IntervalSets, Dates
using DBInterface, DuckDBUtils, DataFrames, JSON3
using Test

const static_dir = joinpath(@__DIR__, "static")

@testset "filtering" begin
    repo = Repository()
    spec = open(JSON3.read, joinpath(static_dir, "data.json"))
    DataIngestion.load_files(repo, spec["files"])

    f1 = DataIngestion.IntervalFilter(
        "hour",
        1 .. 3
    )

    f2 = DataIngestion.ListFilter(
        "cbwd",
        ["NW", "SE"]
    )

    filters = [f1, f2]

    DataIngestion.select(filters, repo)

    df = DBInterface.execute(DataFrame, repo, "FROM selection")
    @test unique(sort(df.cbwd)) == ["NW", "SE"]
    @test unique(sort(df.hour)) == [1, 2, 3]
end

@testset "dates" begin
    repo = Repository()
    path = joinpath(@__DIR__, "static", "dates.csv")
    DataIngestion.load_files(repo, [path], dateformat = "%m/%d/%Y")
    f = IntervalFilter("date", Date(2023, 12, 09)..Date(2023, 12, 10))
    DataIngestion.select([f], repo)
    df = DBInterface.execute(DataFrame, repo, "FROM selection")
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
    d = open(JSON3.read, joinpath(static_dir, "filters.json"))
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
    spec = open(JSON3.read, joinpath(static_dir, "data.json"))
    DataIngestion.load_files(repo, spec["files"])
    info = DataIngestion.summarize(repo, "source")
    df = DBInterface.execute(DataFrame, repo, "FROM source")
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
