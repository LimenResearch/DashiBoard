using Pipelines: @kwarg

# A card whose evaluation depends on how often it has been evaluated before: the state is the
# count, and each evaluation writes it and hands back the next one.
@kwarg struct CountingCard <: Pipelines.StandardCard
    inputs::Vector{String} & (dashi = Pipelines.VARIABLES_DEF,)
end

Pipelines.SourceVariables(c::CountingCard) = Pipelines.SourceVariables(; c.inputs)
Pipelines.output_spec(::CountingCard) = [Pipelines.OutputGroup(Pipelines.OutputSpec(["evaluations"]))]
Pipelines._train(::CountingCard, t, id_var) = nothing
(::CountingCard)(count, t, id_var) = Pipelines.SimpleTable(
    id_var => t[id_var], "evaluations" => fill(count, length(t[id_var]))
)
function Pipelines.evaluate(repository::Repository, c::CountingCard, model, state, sd::Pair, id_var; kwargs...)
    count = something(state, 0) + 1
    cols = Pipelines.evaluate(repository, c, count, sd, id_var; kwargs...)
    return cols, count
end
Pipelines.register_card("counting" => Pipelines.CardSpec(CountingCard, "Counting"))

@testset "stateful card" begin
    node = Node(Pipelines.Card(Dict("type" => "counting", "inputs" => ["TEMP"])))
    Pipelines.train!(repo, node, "selection", "No")
    @test isnothing(get_state(node))

    # Each evaluation sees the state the previous one left on the node.
    evaluations() = only(unique(DBInterface.execute(DataFrame, repo, "FROM counted").evaluations))
    Pipelines.evaljoin(repo, node, "selection" => "counted", "No")
    @test get_state(node) == 1
    @test evaluations() == 1
    Pipelines.evaljoin(repo, node, "selection" => "counted", "No")
    @test get_state(node) == 2
    @test evaluations() == 2

    # A copy carries the state at the time it was made, and moves on independently.
    copy = Pipelines.update_node(node)
    Pipelines.evaljoin(repo, copy, "selection" => "counted", "No")
    @test get_state(copy) == 3
    @test get_state(node) == 2

    # A card that does not use state leaves it as it was.
    plain = Node(Pipelines.Card(Dict("type" => "twofold", "inputs" => ["TEMP"])))
    set_state!(plain, :untouched)
    Pipelines.train_evaljoin!(repo, plain, "selection" => "twofold", "No")
    @test get_state(plain) === :untouched
end
