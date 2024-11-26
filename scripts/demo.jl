using DataIngestion, Pipelines, JSON3, DuckDB, DataFrames
using Scratch: @get_scratch!

load_config = open(JSON3.read, "static/load.json")
pipeline_config = open(JSON3.read, "static/pipeline.json")

repo = Repository(joinpath(@get_scratch!("cache"), "db.duckdb"))
DataIngestion.load_files(repo, joinpath.("data", load_config["files"]))

filters = DataIngestion.Filters(pipeline_config["filters"])
DataIngestion.select(filters, repo)

cards = Pipelines.Cards(pipeline_config["cards"])
Pipelines.evaluate(cards, repo, "selection")

DBInterface.execute(DataFrame, repo, "FROM selection")
