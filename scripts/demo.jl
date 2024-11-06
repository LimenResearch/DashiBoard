using DataIngestion, Pipelines, JSON3, DuckDB, DataFrames

config = open(JSON3.read, "static/demo.json")

my_exp = DataIngestion.Experiment(config["experiment"]; prefix = "cache")

DataIngestion.init!(my_exp; load = true)

filters = DataIngestion.Filters(config["filters"])
DataIngestion.select(filters, my_exp.repository)

cards = Pipelines.Cards(config["cards"])
Pipelines.evaluate(cards, my_exp.repository, "selection")

DBInterface.execute(DataFrame, my_exp.repository, "FROM selection")
