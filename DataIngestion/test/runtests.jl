using DataIngestion
using IntervalSets
using DBInterface, DuckDBUtils, DataFrames, JSON3
using Test

const static_dir = joinpath(@__DIR__, "static")

mktempdir() do dir
    spec = open(JSON3.read, joinpath(static_dir, "data.json"))
    repo = Repository(joinpath(dir, "db.duckdb"))
    DataIngestion.load_files(repo, spec["files"])

    @testset "filtering" begin
        f1 = DataIngestion.IntervalFilter(
            "hour",
            1 .. 3
        )

        f2 = DataIngestion.ListFilter(
            "cbwd",
            ["NW", "SE"]
        )

        filters = DataIngestion.Filters([f1, f2])

        DataIngestion.select(filters, repo)

        df = DBInterface.execute(DataFrame, repo, "FROM selection")
        @test unique(sort(df.cbwd)) == ["NW", "SE"]
        @test unique(sort(df.hour)) == [1, 2, 3]
    end

    @testset "from json" begin
        d = open(JSON3.read, joinpath(static_dir, "filters.json"))
        filters = DataIngestion.Filters(d)

        @test length(filters.filters) == 2
        @test filters.filters[1] isa DataIngestion.IntervalFilter
        @test filters.filters[1].colname == "year"
        @test filters.filters[1].interval == 2011 .. 2012

        @test filters.filters[2] isa DataIngestion.ListFilter
        @test filters.filters[2].colname == "cbwd"
        @test filters.filters[2].list == ["NW", "SW"]
    end

    @testset "summary" begin
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
end
