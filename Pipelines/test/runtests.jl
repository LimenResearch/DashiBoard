using Pipelines, DataIngestion, DBInterface, DataFrames
using Test

@testset "evaluation order" begin
    nodes = [
        Pipelines.Node(["temp"], ["pred humid"], true),
        Pipelines.Node(["pred humid"], ["pred wind"], true),
        Pipelines.Node(["wind", "wind name"], ["pred temp"], true),
        Pipelines.Node(["wind"], ["wind name"], true),
    ]

    @test Pipelines.evaluation_order!(nodes) == [4, 3, 1, 2]

    nodes = [
        Pipelines.Node(["temp"], ["pred humid"], false),
        Pipelines.Node(["pred humid"], ["pred wind"], true),
        Pipelines.Node(["wind", "wind name"], ["pred temp"], false),
        Pipelines.Node(["wind"], ["wind name"], true),
    ]

    @test Pipelines.evaluation_order!(nodes) == [4, 3, 2]
end

mktempdir() do dir
    files = [
        "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
    ]
    my_exp = Experiment(; name = "my_exp", prefix = dir, files)
    DataIngestion.init!(my_exp, load = true)
    filters = DataIngestion.Filters([])
    DataIngestion.select(my_exp.repository, filters)

    @testset "partition" begin
        partition = Pipelines.TiledPartition(["No"], ["cbwd"], [1, 1, 2, 1, 1, 2], "_partition")
        Pipelines.evaluate(partition, my_exp.repository, "selection" => "partition")
        df = DBInterface.execute(DataFrame, my_exp.repository, "FROM partition")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_partition",
        ]
        @test count(==(1), df._partition) == 29218
        @test count(==(2), df._partition) == 14606
        # TODO: test by group as well

        partition = Pipelines.TiledPartition(String[], ["cbwd"], [1, 1, 2, 1, 1, 2], "_partition")
        @test_throws ArgumentError Pipelines.evaluate(partition, my_exp.repository, "selection" => "partition")

        partition = Pipelines.PercentilePartition(["No"], ["cbwd"], 0.9, "partition_var")
        Pipelines.evaluate(partition, my_exp.repository, "selection" => "partition")
        df = DBInterface.execute(DataFrame, my_exp.repository, "FROM partition")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "partition_var",
        ]
        @test count(==(1), df.partition_var) == 39441
        @test count(==(2), df.partition_var) == 4383
        # TODO: port TimeFunnelUtils tests

        partition = Pipelines.PercentilePartition(String[], ["cbwd"], 0.9, "partition_var")
        @test_throws ArgumentError Pipelines.evaluate(partition, my_exp.repository, "selection" => "partition")
    end
end
