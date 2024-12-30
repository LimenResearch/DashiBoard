@testset "parser" begin
    p = default_parser()
    q = StreamlinerCore.Parser(sigmas = Dict("a" => log10))
    r = default_parser(plugins = [q])
    for k in [
            :models, :layers, :aggregators, :metrics, :regularizations,
            :optimizers, :schedules, :stoppers, :devices,
        ]
        @test getfield(r, k) == getfield(p, k)
        @test isempty(getfield(q, k))
    end
    @test r.sigmas == merge(p.sigmas, q.sigmas)
    @test q.sigmas == Dict("a" => log10)
end
