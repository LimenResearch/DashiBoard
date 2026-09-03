using Test, DashiBase
using DashiBase: auto_property, enum_instances, IntegerIR, StringIR, ObjectIR, Maybe
using JSON: JSON
using JSONSchema: Schema

module StructTest
    using StructUtils: @kwarg
    using DashiBase: StringIR, StringDict, DashiBase

    @enum Fruit apple = 1 orange = 2 kiwi = 3

    @kwarg struct MyStruct
        x::Int = 1
        y::String & (dashi = StringIR(enum = ["a", "b"]),)
    end

    @kwarg struct MyStruct2
        x::Int = 1
        y::String & (dashi = StringIR(enum = ["a", "b"]),)
    end

    DashiBase.constraints(::Type{MyStruct2}) = [StringDict("required" => ["x"])]
end

@testset "auto_property" begin
    instances = enum_instances(StructTest.Fruit)
    @test instances == ["apple", "orange", "kiwi"]
    instances = enum_instances(Maybe{StructTest.Fruit})
    @test instances == ["apple", "orange", "kiwi"]

    @test_throws ArgumentError auto_property(Nothing, "k" => nothing)

    prop = auto_property(
        Maybe{StructTest.Fruit},
        "k" => DashiBase.StringIR(title = "fruits"),
        default = StructTest.orange
    )
    @test prop.key == "k"
    @test DashiBase.json_schema(prop.value) == Dict{String, Any}(
        "title" => "fruits",
        "type" => "string",
        "enum" => ["apple", "orange", "kiwi"],
        "default" => "orange",
    )
    @test !prop.required

    prop = auto_property(
        StructTest.Fruit,
        "k" => DashiBase.StringIR(title = "fruits"),
        default = nothing
    )
    @test DashiBase.json_schema(prop.value) == Dict{String, Any}(
        "title" => "fruits",
        "type" => "string",
        "enum" => ["apple", "orange", "kiwi"],
    )
    @test prop.required

    prop = auto_property(
        Maybe{StructTest.Fruit},
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

        prop = auto_property(Maybe{T}, "k" => DashiBase.TrivialIR(), default = def)
        @test DashiBase.json_schema(prop.value) == Dict{String, Any}(
            "type" => s, "default" => ldef, extras...
        )
        @test !prop.required

        prop = auto_property(T, "k" => DashiBase.TrivialIR(), default = nothing)
        @test DashiBase.json_schema(prop.value) == Dict{String, Any}("type" => s, extras...)
        @test prop.required

        prop = auto_property(Maybe{T}, "k" => DashiBase.TrivialIR(), default = nothing)
        @test !prop.required
    end

    prop = auto_property(Matrix, "k" => DashiBase.TrivialIR(), default = nothing)
    @test isempty(DashiBase.json_schema(prop.value)) # we do not write anything for unsupported types
end

@testset "ObjectIR" begin
    obj = ObjectIR(StructTest.MyStruct)
    @test obj.type == "object"

    @test obj.properties[1].key == "x"
    @test JSON.json(obj.properties[1].value) == JSON.json(IntegerIR(default = 1))
    @test !obj.properties[1].required

    @test obj.properties[2].key == "y"
    @test JSON.json(obj.properties[2].value) == JSON.json(StringIR(enum = ["a", "b"]))
    @test obj.properties[2].required

    @test !obj.additionalProperties

    schema = DashiBase.json_schema(obj) |> Schema
    @test isvalid(Dict("y" => "a"), schema)
    @test !isvalid(Dict("y" => "c"), schema)
    @test isvalid(Dict("x" => 1, "y" => "a"), schema)
    @test !isvalid(Dict("x" => 1), schema)

    obj2 = ObjectIR(StructTest.MyStruct2)
    @test obj2.constraints == [Dict("required" => ["x"])]

    schema2 = DashiBase.json_schema(obj2) |> Schema
    @test isvalid(Dict("x" => 1, "y" => "a"), schema2)
    @test !isvalid(Dict("y" => "a"), schema2)
end
