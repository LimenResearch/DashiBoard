@testset "configurations" begin
    model_directory = joinpath(@__DIR__, "static", "model")
    training_directory = joinpath(@__DIR__, "static", "training")
    configs = @with(
        Pipelines.MODEL_DIR => model_directory,
        Pipelines.TRAINING_DIR => training_directory,
        Pipelines.card_configurations()
    )
    @test configs isa AbstractVector
    @test length(configs) == 9
end
