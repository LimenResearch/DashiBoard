using HTTP, DataFrames, JSON3

url = "http://127.0.0.1:8080/"

resp = HTTP.post(url * "load", body = read("static/demo.json", String))
summaries = JSON3.read(resp.body)


resp = HTTP.post(url * "filter", body = read("static/demo.json", String))

resp = HTTP.post(url * "process", body = read("static/demo.json", String))
