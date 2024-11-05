using DataIngestion, Pipelines, JSON3, DuckDB, DataFrames

config = open(JSON3.read, "static/demo.json")

my_exp = DataIngestion.Experiment(config; prefix = "data")

DataIngestion.init!(my_exp; load = true)

filters = DataIngestion.Filters(config)
DataIngestion.select(filters, my_exp.repository)

cards = Pipelines.Cards(config)
tablename = DataIngestion.TABLE_NAMES.selection
Pipelines.evaluate(cards, my_exp.repository, tablename)

DBInterface.execute(DataFrame, my_exp.repository, "FROM $tablename")
