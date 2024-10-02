using JSON3, HTTP, JSONTables, DataFrames

d = Dict(
    "table" => "my_exp_partitioned",
    "filters" => Dict(
        "intervals" => [Dict("colname" => "year", "interval" => Dict("left" => 2011, "right" => 2012))],
        "lists" => [Dict("colname" => "cbwd", "list" => ["NW", "SW"])],
    )
)

url = "http://127.0.0.1:8080/"

resp = HTTP.post(url, body = JSON3.write(d))

DataFrame(jsontable(resp.body))