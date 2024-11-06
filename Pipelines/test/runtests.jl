using Pipelines, DataIngestion, DBInterface, DataFrames, JSON3
using Test

const static_dir = joinpath(@__DIR__, "static")

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
    spec = open(JSON3.read, joinpath(static_dir, "spec.json"))
    my_exp = Experiment(spec["experiment"]; prefix = dir)
    DataIngestion.init!(my_exp, load = true)
    filters = DataIngestion.Filters(spec["filters"])
    DataIngestion.select(filters, my_exp.repository)

    @testset "partition" begin
        d = open(JSON3.read, joinpath(static_dir, "tiledpartition.json"))
        partition = Pipelines.get_card(d)
        Pipelines.evaluate(partition, my_exp.repository, "selection" => "partition")
        df = DBInterface.execute(DataFrame, my_exp.repository, "FROM partition")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_tiled_partition",
        ]
        @test count(==(1), df._tiled_partition) == 29218
        @test count(==(2), df._tiled_partition) == 14606
        # TODO: test by group as well

        partition = Pipelines.TiledPartition(String[], ["cbwd"], [1, 1, 2, 1, 1, 2], "_tiled_partition")
        @test_throws ArgumentError Pipelines.evaluate(partition, my_exp.repository, "selection" => "partition")

        partition = Pipelines.PercentilePartition(["No"], ["cbwd"], 0.9, "_percentile_partition")
        Pipelines.evaluate(partition, my_exp.repository, "selection" => "partition")
        df = DBInterface.execute(DataFrame, my_exp.repository, "FROM partition")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "_percentile_partition",
        ]
        @test count(==(1), df._percentile_partition) == 39441
        @test count(==(2), df._percentile_partition) == 4383
        # TODO: port TimeFunnelUtils tests

        partition = Pipelines.PercentilePartition(String[], ["cbwd"], 0.9, "_percentile_partition")
        @test_throws ArgumentError Pipelines.evaluate(partition, my_exp.repository, "selection" => "partition")
    end

    @testset "cards" begin
        d = open(JSON3.read, joinpath(static_dir, "cards.json"))
        cards = Pipelines.Cards(d)
        Pipelines.evaluate(cards, my_exp.repository, "selection")
        df = DBInterface.execute(DataFrame, my_exp.repository, "FROM selection")
        @test names(df) == [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name",
            "_tiled_partition", "_percentile_partition",
        ]
        @test count(==(1), df._tiled_partition) == 29218
        @test count(==(2), df._tiled_partition) == 14606
        @test count(==(1), df._percentile_partition) == 39441
        @test count(==(2), df._percentile_partition) == 4383
    end
end
