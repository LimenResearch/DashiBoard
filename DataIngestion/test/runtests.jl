using DataIngestion
using IntervalSets
using DuckDB, DataFrames, JSON3
using Test

mktempdir() do dir
    files = [
        "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
    ]
    my_exp = Experiment(; name = "my_exp", prefix = dir, files)
    DataIngestion.init!(my_exp, load = true)

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

        DataIngestion.select(my_exp.repository, filters)

        df = DBInterface.execute(DataFrame, my_exp.repository, "FROM selection")
        @test unique(sort(df.cbwd)) == ["NW", "SE"]
        @test unique(sort(df.hour)) == [1, 2, 3]
    end

    @testset "from json" begin
        fs = [
            Dict(
                "type" => "interval",
                "colname" => "year",
                "interval" => Dict("min" => 2011, "max" => 2012)
            ),
            Dict(
                "type" => "list",
                "colname" => "cbwd",
                "list" => ["NW", "SW"]
            )
        ]
        d = Dict("filters" => fs)
        filters = DataIngestion.Filters(d)

        @test length(filters.filters) == 2
        @test filters.filters[1] isa DataIngestion.IntervalFilter
        @test filters.filters[1].colname == "year"
        @test filters.filters[1].interval == 2011 .. 2012

        @test filters.filters[2] isa DataIngestion.ListFilter
        @test filters.filters[2].colname == "cbwd"
        @test filters.filters[2].list == ["NW", "SW"]

        # Round trip via JSON
        filters = DataIngestion.Filters(JSON3.read(JSON3.write(d)))
        @test length(filters.filters) == 2
        @test filters.filters[1] isa DataIngestion.IntervalFilter
        @test filters.filters[1].colname == "year"
        @test filters.filters[1].interval == 2011 .. 2012

        @test filters.filters[2] isa DataIngestion.ListFilter
        @test filters.filters[2].colname == "cbwd"
        @test filters.filters[2].list == ["NW", "SW"]
    end

    @testset "summary" begin
        info = DataIngestion.summarize(my_exp.repository, "source")
        df = DBInterface.execute(DataFrame, my_exp.repository, "FROM source")
        @test [x.name for x in info] == names(df)

        No_min, No_max = extrema(df.No)
        @test info[1].name == "No"
        @test info[1].type == "numerical"
        @test info[1].summary == (min = No_min, max = No_max, step = round((No_max - No_min) / 100, sigdigits = 2))

        @test info[10].name == "cbwd"
        @test info[10].type == "categorical"
        @test info[10].summary == unique(sort(df.cbwd))
    end
end
