@testset "configurations" begin
    configs = Pipelines.card_configurations()
    @test configs isa AbstractVector
    @test length(configs) == 5
end
