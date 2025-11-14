@testset "card_widgets" begin
    model_directory = joinpath(@__DIR__, "static", "model")
    training_directory = joinpath(@__DIR__, "static", "training")
    configs = @with(
        Pipelines.MODEL_DIR => model_directory,
        Pipelines.TRAINING_DIR => training_directory,
        Pipelines.card_widgets()
    )
    @test configs isa AbstractVector
    @test length(configs) == 10
end
