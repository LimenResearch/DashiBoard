using HTTP: HTTP
using Oxygen: json, @post, serve

using JSON3, DuckDB, Tables

using DataIngestion

@post "/load" function (req::HTTP.Request)
    fs = json(req, DataIngestion.FilesSpec)
    my_exp = Experiment(fs; name = "experiment", prefix = "cache", parent = "data")
    DataIngestion.init!(my_exp)
    return JSON3.write(table)
end

@post "/query" function (req::HTTP.Request)
    query = json(req, DataIngestion.Query)
    table = DBInterface.execute(Tables.columntable, my_exp, query)
    return JSON3.write(table)
end

serve()
