using Pipelines, DataIngestion, DBInterface, DataFrames
using Test

mktempdir() do dir
    files = [
        "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
    ]
    my_exp = Experiment(; name = "my_exp", prefix = dir, files)
    DataIngestion.init!(my_exp, load = true)
    filters = DataIngestion.Filters()
    DataIngestion.select(my_exp.repository, filters)

    @testset "partition" begin
        partition = Pipelines.PartitionSpec(["No"], ["cbwd"], [1, 1, 2, 1, 1, 2])
        Pipelines.evaluate(my_exp.repository, partition, "selection" => "selection")
        df = DBInterface.execute(DataFrame, my_exp.repository, "FROM selection")
        @test count(==(1), df._partition) == 29218
        @test count(==(2), df._partition) == 14606
        # TODO: test by group as well

        partition = Pipelines.PartitionSpec(String[], String[], [1, 1, 2, 1, 1, 2])
        Pipelines.evaluate(my_exp.repository, partition, "selection" => "selection")
        df = DBInterface.execute(DataFrame, my_exp.repository, "FROM selection")
        @test count(==(1), df._partition) == 29216
        @test count(==(2), df._partition) == 14608
    end
end