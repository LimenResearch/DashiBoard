@testset "options" begin
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "options.json"))
    @test Pipelines.extract_options(d, "method", "dbscan") == Dict(
        "radius" => 1.2,
        "min_neighbors" => 5,
        "min_cluster_size" => 12
    )
    @test Pipelines.extract_options(d, "method", "kmeans") == Dict(
        "n_classes" => 7
    )
end
