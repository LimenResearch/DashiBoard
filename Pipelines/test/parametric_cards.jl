@testset "parametric card" begin
    params = Dict("nc" => 3, "vars" => ["a", "b"])
    d = Dict(
        "type" => "cluster",
        "inputs" => [Dict("-s" => "vars"), Dict("-j" => ["pca", Dict("-r" => 3)]), "TEMP"],
        "output" => "cluster",
        "method" => "kmeans",
        "method_options" => Dict(
            "classes" => Dict("-v" => "nc"),
            "iterations" => 100,
            "tol" => 1.0e-6,
            "seed" => 1234
        )
    )
    card = Card(d, params)
    @test card.inputs == ["a", "b", "pca_1", "pca_2", "pca_3", "TEMP"]
    @test card.clusterer.classes == 3
end
