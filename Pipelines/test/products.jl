@testset "several products from one card" begin
    all = ["double", "triple"]

    # Nothing said: every product. The first takes `suffix`, the others their own name.
    card = Pipelines.Card(Dict("type" => "twofold", "inputs" => ["TEMP"]))
    @test Pipelines.selected_products(card) == all
    groups = Pipelines.output_spec(card, false)
    @test [g.name for g in groups] == all
    @test Pipelines.get_node_outputs(Node(card)) == ["TEMP_double", "TEMP_triple"]

    # `suffix` renames the first product only.
    card = Pipelines.Card(Dict("type" => "twofold", "inputs" => ["TEMP"], "suffix" => "x2"))
    @test Pipelines.get_node_outputs(Node(card)) == ["TEMP_x2", "TEMP_triple"]

    # Selecting narrows, keeps the order written, and still names the single product left.
    card = Pipelines.Card(Dict("type" => "twofold", "inputs" => ["TEMP"], "select" => ["triple"]))
    @test [g.name for g in Pipelines.output_spec(card, false)] == ["triple"]
    @test Pipelines.get_node_outputs(Node(card)) == ["TEMP_triple"]
    card = Pipelines.Card(Dict("type" => "twofold", "inputs" => ["TEMP"], "select" => ["triple", "double"]))
    @test Pipelines.get_node_outputs(Node(card)) == ["TEMP_triple", "TEMP_double"]

    # What a selection may not be.
    bad(select; suffix = "double") = Pipelines.product_groups(["TEMP"], select, all, suffix)
    @test_throws ArgumentError bad(String[])                     # nothing to write
    @test_throws ArgumentError bad(["double", "double"])          # the same product twice
    @test_throws ArgumentError bad(["quadruple"])                 # not one this card has
    # Two products with one suffix would write the same columns.
    @test_throws ArgumentError bad(["double", "triple"]; suffix = "triple")

    # A card that does not opt in has no products, and none of this touches it.
    @test isempty(Pipelines.products(Pipelines.Card(Dict("type" => "trivial", "inputs" => ["a"], "outputs" => ["c"]))))

    # And it is written, not only reported.
    card = Pipelines.Card(Dict("type" => "twofold", "inputs" => ["TEMP"]))
    node = Node(card)
    Pipelines.train_evaljoin!(repo, node, "selection" => "twofold", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM twofold")
    @test df.TEMP_double == 2 .* df.TEMP
    @test df.TEMP_triple == 3 .* df.TEMP
end
