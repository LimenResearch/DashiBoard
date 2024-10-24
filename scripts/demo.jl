using DataIngestion, JSON3, DuckDB, DataFrames

files = ["https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv"]

my_exp = Experiment(; name = "my_exp", prefix = "data", files)

DataIngestion.init!(my_exp; load = true)

partition = PartitionSpec(by = ["_name"], sorters = ["year", "month", "day", "hour"], tiles = [1, 1, 2, 1, 1, 2])

register_partition(my_exp, partition)

d = Dict(
    "filters" => Dict(
        "intervals" => [Dict("colname" => "year", "interval" => Dict("left" => 2011, "right" => 2012))],
        "lists" => [Dict("colname" => "cbwd", "list" => ["NW", "SW"])],
    ),
    "select" => ["year", "cbwd", "No"]
)

req_body = JSON3.write(d)

fs = JSON3.read(req_body, DataIngestion.FilterSelect)

DBInterface.execute(DataFrame, my_exp, DataIngestion.Query(fs))
