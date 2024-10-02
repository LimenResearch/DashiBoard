using JSON3, HTTP

d = Dict(
    "table" => "tbl",
    "filters" => Dict(
        "intervals" => [Dict("colname" => "var0", "interval" => Dict("left" => 1.2, "right" => 2.5))],
        "lists" => [Dict("colname" => "var1", "list" => [1, 2, 3])],
    )
)

url = "http://127.0.0.1:8080/"

r = HTTP.post(url, body = JSON3.write(d))
