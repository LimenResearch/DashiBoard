using HTTP: HTTP
using Oxygen: json, @post, serve

using JSON3, DuckDB, Tables

using DataIngestion

files = ["https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv"]

my_exp = Experiment(; name = "my_exp", prefix = "data", files)

DataIngestion.init!(my_exp)

partition = Partition(by = ["_name"], sorters = ["year", "month", "day", "hour"], tiles = [1, 1, 2, 1, 1, 2])

register_partition(my_exp, partition)

@post "/" function (req::HTTP.Request)
    query = json(req, DataIngestion.Query)
    table = DBInterface.execute(Tables.columntable, my_exp, query)
    return JSON3.write(table)
end

serve()
