using DataIngestion
using IntervalSets
using DuckDB, DataFrames
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

    q = DataIngestion.QuerySpec("source", filters, ["hour", "cbwd"])
    query = DataIngestion.Query(q)

    df = DBInterface.execute(DataFrame, my_exp.repository, query)
    @test unique(sort(df.cbwd)) == ["NW", "SE"]
    @test unique(sort(df.hour)) == [1, 2, 3]
    @test names(df) == ["hour", "cbwd"]
end

@testset "partition" begin
    partition = DataIngestion.PartitionSpec(["No"], ["cbwd"], [1, 1, 2, 1, 1, 2])
    DataIngestion.register_partition(my_exp, partition)
    df = DBInterface.execute(DataFrame, my_exp.repository, "FROM partition")
    @test count(==(1), df._partition) == 29218
    @test count(==(2), df._partition) == 14606

    partition = DataIngestion.PartitionSpec(String[], String[], [1, 1, 2, 1, 1, 2])
    DataIngestion.register_partition(my_exp, partition)
    df = DBInterface.execute(DataFrame, my_exp.repository, "FROM partition")
    @test count(==(1), df._partition) == 29216
    @test count(==(2), df._partition) == 14608
end

# TODO: test QuerySpec construction from JSON
# TODO: test summary
