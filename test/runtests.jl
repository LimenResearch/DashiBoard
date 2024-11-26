using HTTP, DataIngestion, Pipelines, JSON3, DuckDB, DataFrames
using DashiBoard
using Scratch: @get_scratch!
using Test

const static_dir = joinpath(@__DIR__, "static")
const data_dir = joinpath(dirname(@__DIR__), "dashiboard", "data")

load_config = open(JSON3.read, joinpath(static_dir, "load.json"))
pipeline_config = open(JSON3.read, joinpath(static_dir, "pipeline.json"))

repo = Repository(joinpath(@get_scratch!("cache"), "db.duckdb"))
DataIngestion.load_files(repo, joinpath.(data_dir, load_config["files"]))

filters = DataIngestion.Filters(pipeline_config["filters"])
DataIngestion.select(filters, repo)

cards = Pipelines.Cards(pipeline_config["cards"])
Pipelines.evaluate(cards, repo, "selection")

res = DBInterface.execute(DataFrame, repo, "FROM selection")

@testset "cards" begin
    @test "_tiled_partition" in names(res)
    @test "_percentile_partition" in names(res)
end

DBInterface.close!(repo.db)

server = DashiBoard.launch(; async = true)

@testset "request" begin
    url = "http://127.0.0.1:8080/"

    resp = HTTP.post(url * "load", body = read(joinpath(static_dir, "load.json"), String))
    summaries = JSON3.read(resp.body)
    @test summaries[end]["name"] == "_name"

    resp = HTTP.post(url * "pipeline", body = read(joinpath(static_dir, "pipeline.json"), String))
    summaries = JSON3.read(resp.body)

    @test summaries[end]["name"] == "_percentile_partition"
end

DashiBoard.close!()

close(server)