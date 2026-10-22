using Test, DashiBase
using DashiBase: auto_property, enum_instances,
    TrivialIR, IntegerIR, NumericIR, StringIR,
    ArrayIR, ObjectIR, TaggedObjectIR, OneOrManyIR,
    EitherIR, MapIR, AbstractIR, Maybe
using StructUtils: StructUtils
using JSON: JSON
using JSONSchema: JSONSchema, Schema

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

    @kwarg struct MyStruct3
        x::Bool = true
    end

    abstract type Shape end

    @kwarg struct Circle <: Shape
        radius::Float64 = 1.0
    end
    @kwarg struct Square <: Shape
        side::Float64 = 1.0
    end
    DashiBase.@options Shape Dict("circle" => Circle, "square" => Square)

    @kwarg struct Drawing
        shape::Shape = Square()
    end
end

module MethodTest
    using StructUtils: @kwarg
    using DashiBase: DashiBase, AbstractMethod, ArrayIR, @options

    abstract type Scaling <: AbstractMethod end

    @kwarg struct Identity <: Scaling end

    @kwarg struct Fixed <: Scaling
        factor::Float64
    end

    @kwarg struct PerColumn <: Scaling
        factors::Vector{Float64}
    end

    const SCALINGS = Dict{String, Type}("identity" => Identity, "fixed" => Fixed, "per_column" => PerColumn)

    @options Scaling SCALINGS

    # Written by hand: only that the list needs at least one entry. What an entry can be is left
    # for DashiBase to work out from the field's type.
    @kwarg struct Combined
        steps::Vector{Scaling} & (dashi = ArrayIR(minItems = 1),)
    end
end

@testset "auto_property" begin
    instances = enum_instances(StructTest.Fruit)
    @test instances == ["apple", "orange", "kiwi"]
    instances = enum_instances(Maybe{StructTest.Fruit})
    @test instances == ["apple", "orange", "kiwi"]

    @test_throws ArgumentError auto_property(Nothing, "k" => nothing)

    prop = auto_property(
        Maybe{StructTest.Fruit},
        "k" => StringIR(title = "fruits"),
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
        "k" => StringIR(title = "fruits"),
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
        "k" => StringIR(title = "fruits"),
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

        prop = auto_property(Maybe{T}, "k" => TrivialIR(), default = def)
        @test DashiBase.json_schema(prop.value) == Dict{String, Any}(
            "type" => s, "default" => ldef, extras...
        )
        @test !prop.required

        prop = auto_property(T, "k" => TrivialIR(), default = nothing)
        @test DashiBase.json_schema(prop.value) == Dict{String, Any}("type" => s, extras...)
        @test prop.required

        prop = auto_property(Maybe{T}, "k" => TrivialIR(), default = nothing)
        @test !prop.required
    end

    prop = auto_property(Matrix, "k" => TrivialIR(), default = nothing)
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

    obj3 = ObjectIR(StructTest.MyStruct3)
    @test obj3.properties[1].value.default == true

    schema3 = DashiBase.json_schema(obj3) |> Schema
    @test isvalid(Dict("x" => true), schema3)
    @test !isvalid(Dict("x" => 1), schema3)
end

@testset "ArrayIR" begin
    obj = ObjectIR(StructTest.MyStruct)
    arr = ArrayIR(items = obj, minItems = 2)
    schema = DashiBase.json_schema(arr) |> Schema
    d = Dict("x" => 1, "y" => "a")
    d1 = Dict("y" => "c")
    @test !isvalid(d, schema)
    @test !isvalid([d], schema)
    @test isvalid([d, d], schema)
    @test !isvalid([d, d1], schema)

    one_or_many = OneOrManyIR(items = obj, maxItems = 2)
    schema = DashiBase.json_schema(one_or_many) |> Schema
    @test isvalid(d, schema)
    @test !isvalid(d1, schema)
    @test isvalid([d], schema)
    @test !isvalid([d1], schema)
    @test isvalid([d, d], schema)
    @test !isvalid([d, d, d], schema)

    @test_throws ArgumentError OneOrManyIR(items = arr)
end

# A list says when a value makes sense at most once; a form draws such a set as on/off choices
# and anything else as a sequence, where repeats are meant.
@testset "uniqueItems" begin
    set = ArrayIR(items = StringIR(enum = ["a", "b"]), uniqueItems = true)
    @test DashiBase.json_schema(set)["uniqueItems"] == true
    schema = DashiBase.json_schema(set) |> Schema
    @test isvalid(["a", "b"], schema)
    @test !isvalid(["a", "a"], schema)
    sequence = ArrayIR(items = IntegerIR(enum = [1, 2]))
    @test !haskey(DashiBase.json_schema(sequence), "uniqueItems")
    @test isvalid([1, 1, 2], DashiBase.json_schema(sequence) |> Schema)
end

@testset "IR serialises to JSON" begin
    @test JSON.json(TrivialIR()) == "{\"type\":\"trivial\"}"
    @test DashiBase.json_schema(TrivialIR()) == Dict{String, Any}()
    @test JSON.json(ArrayIR(items = TrivialIR()); omit_null = true) ==
        """{"type":"array","items":{"type":"trivial"}}"""
    @test DashiBase.json_schema(ArrayIR(items = TrivialIR())) ==
        Dict{String, Any}("type" => "array", "items" => Dict())
end

@testset "every IR node is self-describing" begin
    # A renderer dispatches on `type`, and `choose_IR` deserialises on it. `OneOrManyIR` used to
    # carry neither, so a one-or-many field -- the node the group dialect leans on hardest --
    # arrived as {array, eltype} that nothing could identify.
    one_or_many = OneOrManyIR(items = StringIR(), eltype = "string")
    @test one_or_many.type == "one_or_many"
    @test JSON.parse(JSON.json(one_or_many; omit_null = true))["type"] == "one_or_many"

    # and the schema projection is unchanged by that: it builds its own dict
    @test DashiBase.json_schema(one_or_many)["type"] == ["string", "array"]
end

@testset "EitherIR" begin
    step = ObjectIR(properties = [DashiBase.Property("node" => StringIR(enum = ["a", "b"]))])
    either = EitherIR(["string" => StringIR(enum = ["a", "b"]), "object" => step])
    @test either.type == "either"
    @test either.types == ["string", "object"]

    # The schema branches on the value's own JSON type, the way `OneOrManyIR` does. A failure
    # inside a branch is then reported by that branch's keyword — `enum` — rather than as a bare
    # "none of these matched", so a form can still say which values would have been accepted.
    schema = DashiBase.json_schema(either)
    @test schema["type"] == ["string", "object"]
    @test schema["allOf"][1]["if"] == Dict("type" => "string")
    @test schema["allOf"][1]["then"]["enum"] == ["a", "b"]
    @test schema["allOf"][2]["then"]["type"] == "object"

    # Two options of one JSON type could not be told apart by the value.
    @test_throws ArgumentError EitherIR(["string" => StringIR(), "string" => StringIR()])
    # and it announces itself, like every other node
    @test JSON.parse(JSON.json(either; omit_null = true))["type"] == "either"
end

@testset "a map of names to values of one kind" begin
    ir = MapIR(values = StringIR(enum = ["log", "sqrt"]), keys_from = "inputs")
    @test ir.type == "map"
    schema = DashiBase.json_schema(ir)
    @test schema == Dict{String, Any}(
        "type" => "object",
        "additionalProperties" => Dict{String, Any}("type" => "string", "enum" => ["log", "sqrt"]),
    )
    # The form reads the IR, where the list the keys come from is named.
    parsed = JSON.parse(JSON.json(ir; omit_null = true))
    @test parsed["keys_from"] == "inputs"
    @test parsed["values"]["enum"] == ["log", "sqrt"]
    # A document is checked against it: any key, values of the one kind.
    s = Schema(schema)
    @test isnothing(JSONSchema.validate(Dict("TEMP" => "log"), s))
    @test !isnothing(JSONSchema.validate(Dict("TEMP" => "cube"), s))
end

@testset "a tagged object that says where its options come from" begin
    branch = ObjectIR(properties = [DashiBase.Property("features" => IntegerIR())])
    tagged = TaggedObjectIR(objects = Dict("dense" => branch), options_from = "model")
    @test tagged.options_from == "model"
    @test JSON.parse(JSON.json(tagged; omit_null = true))["options_from"] == "model"
    # The schema is unchanged by it: it checks the same documents.
    @test !haskey(DashiBase.json_schema(tagged), "options_from")
    @test DashiBase.json_schema(tagged) == DashiBase.json_schema(TaggedObjectIR(objects = Dict("dense" => branch)))
end

# A variant whose default is an instance names the option that instance belongs to.
@testset "a variant whose default is an instance" begin
    ir = only(ObjectIR(StructTest.Drawing).properties).value
    @test ir.default_option == "square"
end

@testset "a hand-written rule on a list of methods" begin
    steps = only(ObjectIR(MethodTest.Combined).properties).value
    @test steps.minItems == 1
    @test steps.items isa TaggedObjectIR
    choices = steps.items.objects
    @test issetequal(keys(choices), ["identity", "fixed", "per_column"])
    @test isempty(choices["identity"].properties)
    factor = only(choices["fixed"].properties)
    @test factor.key == "factor" && factor.value isa NumericIR
    factors = only(choices["per_column"].properties)
    @test factors.key == "factors" && factors.value isa ArrayIR
end

@testset "deserializing IR" begin
    d = Dict(
        "type" => "array",
        "items" => Dict("type" => "integer", "minimum" => 1),
        "minItems" => 1
    )
    widths = StructUtils.make(AbstractIR, d)
    @test widths isa ArrayIR
    @test widths.items isa IntegerIR
    @test widths.minItems == 1

    d["default"] = [64, 32]
    widths = StructUtils.make(AbstractIR, d)
    @test widths.default == [64, 32]
end

@testset "json-rpc" begin
    handlers = Dict{String, Any}("echo" => p -> (() -> p))
    rpc(s) = JSON.parse(JSON.json(DashiBase.apply_handlers(handlers, s)))

    ok = rpc("""{"jsonrpc":"2.0","id":1,"method":"echo","params":{"a":1}}""")
    @test ok == Dict("jsonrpc" => "2.0", "id" => 1, "result" => Dict("a" => 1))

    for bad in ("""{"id":1,"method":"echo","params":1}""", """{"jsonrpc":"1.0","id":1,"method":"echo","params":1}""")
        @test rpc(bad)["error"]["code"] == -32600
    end
    for id in ("\"abc\"", "1.5", "true")
        r = rpc("""{"jsonrpc":"2.0","id":$(id),"method":"echo","params":1}""")
        @test r["error"]["code"] == -32600 && r["id"] === nothing
    end
    @test rpc("""{"jsonrpc":"2.0","id":2,"method":"nope","params":1}""")["error"]["code"] == -32601
    @test rpc("{bad")["error"]["code"] == -32700

    batch = rpc("""[
        {"jsonrpc":"2.0","id":1,"method":"echo","params":1},
        {"jsonrpc":"2.0","method":"echo","params":2},
        {"jsonrpc":"2.0","id":3,"method":"nope","params":3},
        {"jsonrpc":"2.0","id":4}
    ]""")
    @test [r["id"] for r in batch] == [1, 3, 4]
    @test batch[1]["result"] == 1 && batch[2]["error"]["code"] == -32601 && batch[3]["error"]["code"] == -32600
    @test DashiBase.apply_handlers(handlers, """[{"jsonrpc":"2.0","method":"echo","params":1}]""") === nothing
    # An element that is not an object is answered in its own slot, not by crashing the batch.
    mixed = rpc("""[1, {"jsonrpc":"2.0","id":5,"method":"echo","params":5}]""")
    @test mixed[1]["error"]["code"] == -32600 && mixed[2]["result"] == 5

    streamed = DashiBase.apply_handlers(handlers, """[{"jsonrpc":"2.0","id":1,"method":"echo","params":1}]""", tempname())
    @test streamed isa DashiBase.JSONFailure && streamed.error.code == -32600

    failure = DashiBase.json_error(DashiBase.internal_error, DashiBase.StructuredException(Dict{String, Any}("k" => 1)))
    @test JSON.parse(JSON.json(failure))["data"] == Dict("k" => 1)
end
