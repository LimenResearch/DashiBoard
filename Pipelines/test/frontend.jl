@testset "configurations" begin
    configs = Pipelines.card_configurations(
        streamliner = (
            model_directory = joinpath(@__DIR__, "static", "model"),
            training_directory = joinpath(@__DIR__, "static", "training"),
        )
    )
    @test configs isa AbstractVector
    @test length(configs) == 6
end
