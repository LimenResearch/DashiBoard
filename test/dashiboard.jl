using HTTP, DataIngestion, Pipelines, JSON3, DBInterface, DataFrames
using DashiBoard
using Scratch: @get_scratch!
using Test
using Downloads: download

mktempdir() do data_dir
    download(
        "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
        joinpath(data_dir, "pollution.csv")
    )

    load_config = open(JSON3.read, joinpath(@__DIR__, "static", "load.json"))
    pipeline_config = open(JSON3.read, joinpath(@__DIR__, "static", "pipeline.json"))

    repo = DashiBoard.REPOSITORY[]
    DataIngestion.load_files(repo, joinpath.(data_dir, load_config["files"]))

    filters = DataIngestion.get_filter.(pipeline_config["filters"])
    DataIngestion.select(repo, filters)

    cards = Pipelines.get_card.(pipeline_config["cards"])
    Pipelines.evaluate(repo, cards, "selection")

    res = DBInterface.execute(DataFrame, repo, "FROM selection")

    @testset "cards" begin
        @test "_tiled_partition" in names(res)
        @test "_percentile_partition" in names(res)
    end

    static_directory = joinpath(@__DIR__, "..", "static")
    model_directory = joinpath(static_directory, "model")
    training_directory = joinpath(static_directory, "training")

    server = DashiBoard.launch(
        data_dir;
        async = true,
        model_directory,
        training_directory
    )

    @testset "request" begin
        url = "http://127.0.0.1:8080/"

        body = read(joinpath(@__DIR__, "static", "card-configurations.json"), String)
        resp = HTTP.post(url * "card-configurations", body = body)
        configs = JSON3.read(resp.body)
        @test configs isa AbstractVector
        @test length(configs) == 8

        body = read(joinpath(@__DIR__, "static", "load.json"), String)
        resp = HTTP.post(url * "load", body = body)
        summaries = JSON3.read(resp.body)
        @test summaries[end]["name"] == "_name"

        body = read(joinpath(@__DIR__, "static", "pipeline.json"), String)
        resp = HTTP.post(url * "pipeline", body = body)
        summaries = JSON3.read(resp.body)["summaries"]

        @test summaries[end]["name"] == "_percentile_partition"

        HTTP.open("GET", url * "processed-data", headers = Dict("Connection" => "close")) do stream
            r = startread(stream)
            io = IOBuffer()
            write(io, stream)
            data = take!(io)

            @test length(data) == 360326
            @test r.headers == [
                "Connection" => "close",
                "Content-Type" => "text/csv",
                "Transfer-Encoding" => "chunked",
                "Content-Length" => "360326",
            ]
        end
    end

    close(server)
end
