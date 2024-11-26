using DataIngestion, Pipelines, JSON3, DuckDB, DataFrames
using Scratch: @get_scratch!
using Test

const static_dir = joinpath(@__DIR__, "static")

load_config = open(JSON3.read, joinpath(static_dir, "load.json"))
pipeline_config = open(JSON3.read, joinpath(static_dir, "pipeline.json"))

repo = Repository(joinpath(@get_scratch!("cache"), "db.duckdb"))
DataIngestion.load_files(repo, joinpath.("dashiboard", "data", load_config["files"]))

filters = DataIngestion.Filters(pipeline_config["filters"])
DataIngestion.select(filters, repo)

cards = Pipelines.Cards(pipeline_config["cards"])
Pipelines.evaluate(cards, repo, "selection")

res = DBInterface.execute(DataFrame, repo, "FROM selection")

@testset "cards" begin
    @test "_tiled_partition" in names(res)
    @test "_percentile_partition" in names(res)
end
