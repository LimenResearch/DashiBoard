using Test, DashiBase

module StructTest
    using StructUtils: @kwarg
    @enum Fruit apple = 1 orange = 2 kiwi = 3

    @kwarg struct MyStruct
        x::Int = 1
        y::String & (dashi = StringIR(enum = ["a", "b"]),)
    end
end

@testset "auto_property" begin
    instances = DashiBase.enum_instances(StructTest.Fruit)
    @test instances == ["apple", "orange", "kiwi"]
    instances = DashiBase.enum_instances(Union{StructTest.Fruit, Nothing})
    @test instances == ["apple", "orange", "kiwi"]

    @test_throws ArgumentError DashiBase.auto_property(Nothing, "k" => nothing)

    prop = DashiBase.auto_property(
        Union{StructTest.Fruit, Nothing},
        "k" => DashiBase.StringIR(title = "fruits"),
        default = StructTest.orange
    )
    @test prop.key == "k"
    @test DashiBase.emit_json(prop.value) == Dict{String, Any}(
        "title" => "fruits",
        "type" => "string",
        "enum" => ["apple", "orange", "kiwi"],
        "default" => "orange",
    )
    @test !prop.required

    prop = DashiBase.auto_property(
        StructTest.Fruit,
        "k" => DashiBase.StringIR(title = "fruits"),
        default = nothing
    )
    @test DashiBase.emit_json(prop.value) == Dict{String, Any}(
        "title" => "fruits",
        "type" => "string",
        "enum" => ["apple", "orange", "kiwi"],
    )
    @test prop.required

    prop = DashiBase.auto_property(
        Union{StructTest.Fruit, Nothing},
        "k" => DashiBase.StringIR(title = "fruits"),
        default = nothing
    )
    @test !prop.required

    for (T, s, def, ldef) in [
            (Integer, "integer", 0, 0),
            (Number, "number", 0.0, 0.0),
            (String, "string", "abc", "abc"),
            (Symbol, "string", :abc, "abc"),
            (AbstractVector, "array", [1, 2], [1, 2]),
            (Vector{String}, "array", ["a", "b"], ["a", "b"]),
        ]

        extras = T === AbstractVector ? ["items" => Dict()] :
            T === Vector{String} ? ["items" => Dict("type" => "string")] : []

        prop = DashiBase.auto_property(Union{T, Nothing}, "k" => DashiBase.TrivialIR(), default = def)
        @test DashiBase.emit_json(prop.value) == Dict{String, Any}(
            "type" => s, "default" => ldef, extras...
        )
        @test !prop.required

        prop = DashiBase.auto_property(T, "k" => DashiBase.TrivialIR(), default = nothing)
        @test DashiBase.emit_json(prop.value) == Dict{String, Any}("type" => s, extras...)
        @test prop.required

        prop = DashiBase.auto_property(Union{T, Nothing}, "k" => DashiBase.TrivialIR(), default = nothing)
        @test !prop.required
    end

    prop = DashiBase.auto_property(Matrix, "k" => DashiBase.TrivialIR(), default = nothing)
    @test isempty(DashiBase.emit_json(prop.value)) # we do not write anything for unsupported types
end
