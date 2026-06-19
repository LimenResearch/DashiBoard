@testset "groups" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "groups.json"))
    g, grps, cols = Pipelines.generate_dag(d["nodes"], d["groups"])
    es = sort(collect(edges(g)))

    @test grps == ["weather"]
    @test length(es) == 3
    @test Pair(es[1]) == (2 => 3)
    @test Pair(es[2]) == (4 => 1)
    @test Pair(es[3]) == (4 => 3)

    @test cols == ["cbwd", "No", "PRES", "TEMP"] # TODO: consider keeping them grouped
end
