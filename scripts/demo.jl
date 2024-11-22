using DataIngestion, Pipelines, JSON3, DuckDB, DataFrames

load_config = open(JSON3.read, "static/load.json")
pipeline_config = open(JSON3.read, "static/pipeline.json")

repo = Repository(joinpath("cache", "db.duckdb"))
DataIngestion.load_files(repo, joinpath.("data", load_config["files"]))

filters = DataIngestion.Filters(pipeline_config["filters"])
DataIngestion.select(filters, repo)

cards = Pipelines.Cards(pipeline_config["cards"])
Pipelines.evaluate(cards, repo, "selection")

DBInterface.execute(DataFrame, repo, "FROM selection")
