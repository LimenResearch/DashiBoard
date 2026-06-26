@testset "groups" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "groups.json"))
    g, (grp_keys, grp_vals), cols = Pipelines.generate_dag(d["nodes"], d["groups"])
    es = sort(collect(edges(g)))

    @test grp_keys == ["weather"]
    @test grp_vals == [Dict("cols" => ["PRES", "TEMP"])]

    @test length(es) == 5
    @test Pair(es[1]) == (1 => 3)
    @test Pair(es[2]) == (2 => 3)
    @test Pair(es[3]) == (4 => 1)
    @test Pair(es[4]) == (5 => 1)
    @test Pair(es[5]) == (5 => 3)

    @test cols == ["cbwd", "No", "PRES", "TEMP"] # TODO: consider keeping them grouped
end

@testset "node_digraph" begin
    spec = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "spec.json"))
    repo = Repository()

    mktempdir() do dir
        Downloads.download(
            "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
            joinpath(dir, "pollution.csv")
        )
        DataIngestion.load_files(repo, dir, spec["data"])
    end
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "groups.json"))
    pipeline = Pipelines.Pipeline(d["nodes"], d["groups"])
    Pipelines.train_evaljoin!(repo, pipeline, "source", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM source")
    @test names(df) == [
        "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
        "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "No_log", "partition",
        "PRES_rescaled", "TEMP_rescaled", "No_rescaled", "component_1", "component_2",
    ]
end
