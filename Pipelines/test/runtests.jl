using Pipelines
using Test

@testset "Pipelines.jl" begin
    # Write your tests here.
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
