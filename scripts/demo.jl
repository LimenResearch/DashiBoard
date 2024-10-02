using DataIngestion, JSON3, DuckDB, DataFrames

files = ["https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv"]

my_exp = Experiment(; name = "my_exp", prefix = "data", files)

DataIngestion.init!(my_exp)

partition = Partition(by = ["_name"], sorters = ["year", "month", "day", "hour"], tiles = [1, 1, 2, 1, 1, 2])

register_partition(my_exp, partition)

d = Dict(
    "table" => "my_exp_partitioned",
    "filters" => Dict(
        "intervals" => [Dict("colname" => "year", "interval" => Dict("left" => 2011, "right" => 2012))],
        "lists" => [Dict("colname" => "cbwd", "list" => ["NW", "SW"])],
    )
)

req_body = JSON3.write(d)

query = JSON3.read(req_body, DataIngestion.Query)

DBInterface.execute(DataFrame, my_exp, query)
