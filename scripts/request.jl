using HTTP, DataFrames, JSON3

url = "http://127.0.0.1:8080/"

resp = HTTP.post(url * "load", body = read("static/load.json", String))
summaries = JSON3.read(resp.body)

resp = HTTP.post(url * "pipeline", body = read("static/pipeline.json", String))
summaries = JSON3.read(resp.body)
