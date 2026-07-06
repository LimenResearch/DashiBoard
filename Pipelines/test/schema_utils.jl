module EnumTest
    @enum Fruit apple = 1 orange = 2 kiwi = 3
end

@testset "schema from type" begin
    instances = Pipelines.enum_instances(EnumTest.Fruit)
    @test instances == ["apple", "orange", "kiwi"]
    instances = Pipelines.enum_instances(Union{EnumTest.Fruit, Nothing})
    @test instances == ["apple", "orange", "kiwi"]

    @test_throws ArgumentError Pipelines.schema_from_type(Nothing, Dict(), nothing)

    schema, is_required = Pipelines.schema_from_type(
        Union{EnumTest.Fruit, Nothing},
        Dict("title" => "fruits"),
        EnumTest.orange
    )
    @test schema == Dict{String, Any}(
        "title" => "fruits",
        "type" => "string",
        "enum" => ["apple", "orange", "kiwi"],
        "default" => "orange",
    )
    @test !is_required

    schema, is_required = Pipelines.schema_from_type(
        EnumTest.Fruit,
        Dict("title" => "fruits"),
        nothing
    )
    @test schema == Dict{String, Any}(
        "title" => "fruits",
        "type" => "string",
        "enum" => ["apple", "orange", "kiwi"],
    )
    @test is_required

    _, is_required = Pipelines.schema_from_type(
        Union{EnumTest.Fruit, Nothing},
        Dict("title" => "fruits"),
        nothing
    )
    @test !is_required

    for (T, s, def, ldef) in [
            (Integer, "integer", 0, 0),
            (Number, "number", 0.0, 0.0),
            (String, "string", "abc", "abc"),
            (Symbol, "string", :abc, "abc"),
            (AbstractVector, "array", [1, 2], [1, 2]),
        ]

        schema, is_required = Pipelines.schema_from_type(Union{T, Nothing}, Dict(), def)
        @test schema == Dict{String, Any}("type" => s, "default" => ldef)
        @test !is_required

        schema, is_required = Pipelines.schema_from_type(T, Dict(), nothing)
        @test schema == Dict{String, Any}("type" => s)
        @test is_required

        _, is_required = Pipelines.schema_from_type(Union{T, Nothing}, Dict(), nothing)
        @test !is_required
    end

    @test_throws ArgumentError  Pipelines.schema_from_type(Matrix, Dict(), nothing)
end
