@testset "parser" begin
    p = default_parser()
    p1 = default_parser(plugins = Any[])
    for k in fieldnames(StreamlinerCore.Parser)
        @test getfield(p1, k) == getfield(p, k)
    end
    @test_throws ArgumentError default_parser(plugins = [Dict()])

    q = StreamlinerCore.Parser(sigmas = Dict("a" => log10))
    @test q.sigmas == Dict("a" => log10)

    for r in [default_parser(plugins = [q]), default_parser(plugins = Any[q])]
        @test r.sigmas == merge(p.sigmas, q.sigmas)
        for k in fieldnames(StreamlinerCore.Parser)
            k == :sigmas && continue
            @test getfield(r, k) == getfield(p, k)
            @test isempty(getfield(q, k))
        end
    end
end
