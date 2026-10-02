using StreamlinerCore: @kwarg
using DashiBase: DashiBase
using Base.ScopedValues: @with

# A reader an extension would register: one setting, nothing else.
@kwarg struct TestReader
    channels::Int = 1
end

@testset "loaders" begin
    SC = StreamlinerCore
    # Out of the box there is the default alone: rows are read as they are.
    ir = SC.loader_IR()
    @test ir.options == [""] && ir.default_option == ""
    @test isempty(ir.objects[""].properties)
    @test SC.make_loader(Dict{String, Any}()) isa SC.RowLoader
    @test isnothing(SC.input_paths(SC.RowLoader()))
    @test SC.get_metadata(SC.RowLoader()) == Dict{String, Any}("type" => "")

    parser = SC.default_parser(plugins = [SC.Parser(loaders = Dict{String, Any}("test" => TestReader))])
    @with SC.PARSER => parser begin
        ir = SC.loader_IR()
        @test issetequal(ir.options, ["", "test"])
        # A file loader is the two path columns plus the reader's own settings, in one object.
        @test [p.key for p in ir.objects["test"].properties] == ["input_paths", "target_paths", "channels"]
        @test !isempty(ir.objects["test"].constraints)

        loader = SC.make_loader(Dict{String, Any}("type" => "test", "input_paths" => "frame", "channels" => 3))
        @test loader isa SC.FileLoader{TestReader}
        @test SC.input_paths(loader) == "frame" && isnothing(SC.target_paths(loader))
        @test loader.reader.channels == 3
        @test SC.make_loader(SC.get_metadata(loader)) == loader

        # A file loader that names no path column reads nothing.
        @test_throws ArgumentError SC.make_loader(Dict{String, Any}("type" => "test"))
        @test_throws ArgumentError SC.make_loader(Dict{String, Any}("type" => "nosuch"))
    end
end

@testset "a struct written flat over another" begin
    SC = StreamlinerCore
    inner = DashiBase.ObjectIR(TestReader)
    inside, outside = SC.split_config(inner, Dict{String, Any}("channels" => 2, "other" => 1))
    @test inside == Dict{String, Any}("channels" => 2)
    @test outside == Dict{String, Any}("other" => 1)
end
