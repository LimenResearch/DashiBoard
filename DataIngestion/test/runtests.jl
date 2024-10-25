using DataIngestion
using IntervalSets
using DuckDB, DataFrames, JSON3
using Test

begin
    files = [
        "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
    ]
    my_exp = Experiment(; name = "my_exp", prefix = "data", files)
    DataIngestion.init!(my_exp, load = true)
end

@testset "filtering" begin
    f1 = DataIngestion.IntervalFilter(
        "hour",
        1 .. 3
    )

    f2 = DataIngestion.ListFilter(
        "cbwd",
        ["NW", "SE"]
    )

    filters = DataIngestion.Filters(
        [f1],
        [f2]
    )

    q = DataIngestion.FilterSelect(filters, ["hour", "cbwd", "No"])
    query = DataIngestion.Query(q)

    df = DBInterface.execute(DataFrame, my_exp.repository, query)
    @test unique(sort(df.cbwd)) == ["NW", "SE"]
    @test unique(sort(df.hour)) == [1, 2, 3]
    @test names(df) == ["hour", "cbwd", "No"]
end

@testset "from json" begin
    d = Dict(
        "filters" => Dict(
            "intervals" => [Dict("colname" => "year", "interval" => Dict("left" => 2011, "right" => 2012))],
            "lists" => [Dict("colname" => "cbwd", "list" => ["NW", "SW"])],
        ),
        "select" => ["year", "cbwd", "No"]
    )

    fs = JSON3.read(JSON3.write(d), DataIngestion.FilterSelect)

    @test length(fs.filters.intervals) == 1
    @test fs.filters.intervals[1].colname == "year"
    @test fs.filters.intervals[1].interval == 2011 .. 2012

    @test length(fs.filters.lists) == 1
    @test fs.filters.lists[1].colname == "cbwd"
    @test fs.filters.lists[1].list == ["NW", "SW"]

    @test fs.select == ["year", "cbwd", "No"]
end

@testset "partition" begin
    partition = DataIngestion.PartitionSpec(["No"], ["cbwd"], [1, 1, 2, 1, 1, 2])
    DataIngestion.register_partition(my_exp.repository, partition, "source" => "partition")
    df = DBInterface.execute(DataFrame, my_exp.repository, "FROM partition")
    @test count(==(1), df._partition) == 29218
    @test count(==(2), df._partition) == 14606

    partition = DataIngestion.PartitionSpec(String[], String[], [1, 1, 2, 1, 1, 2])
    DataIngestion.register_partition(my_exp.repository, partition, "source" => "partition")
    df = DBInterface.execute(DataFrame, my_exp.repository, "FROM partition")
    @test count(==(1), df._partition) == 29216
    @test count(==(2), df._partition) == 14608
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
