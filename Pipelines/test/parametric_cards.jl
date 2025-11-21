@testset "parametric card" begin
    params = Dict("nc" => 3, "vars" => ["a", "b"])
    d = Dict(
        "type" => "cluster",
        "inputs" => [Dict("-s" => "vars"), Dict("-j" => ["component", Dict("-r" => 3)]), "TEMP"],
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
    @test card.inputs == ["a", "b", "component_1", "component_2", "component_3", "TEMP"]
    @test card.clusterer.classes == 3

    d = TOML.parse(
        """
        type = "cluster"
        method = "kmeans"
        method_options = {classes = {"-v" = "nclasses"}}
        inputs = [
            {"-j" = ["component", {"-r" = 3}]},
            {"-j" = [["wind", "temperature"], ["10m", "20m"]]},
            {"-s" = "additional_input_vars"},
            "humidity"
        ]
        """
    )
    ps = TOML.parse(
        """
        nclasses = 3
        additional_input_vars = ["precipitation", "irradiance"]
        """
    )

    d1 = Pipelines.apply_helpers(
        Pipelines.DEFAULT_DICT_HELPERS[], d, ps;
        max_rec = Pipelines.DEFAULT_MAX_REC[]
    )

    card = Pipelines.Card(d, ps)

    @test card.clusterer.classes == 3
    @test card.inputs == ["component_1", "component_2", "component_3", "wind_10m", "wind_20m", "temperature_10m", "temperature_20m", "precipitation", "irradiance", "humidity"]
end
