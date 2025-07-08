@testset "colnames" begin
    col = "temp"
    suffix = "hat"
    i = 3
    @test Pipelines.join_names(col, suffix, i) == "temp_hat_3"
    c = Pipelines.new_name("a", ["a_1", "b", "a_3"])
    @test c == "a_2"
    c = Pipelines.new_name("a", ["b"])
    @test c == "a_1"
end

@testset "counting_sort!" begin
    ps = [2 => 5, 2 => 4, 1 => 7, 0 => 9, 11 => 3, 1 => 6, -1 => 4]
    byfirst = Pipelines.counting_sort!(similar(ps), ps, by = first)
    perm = [7, 4, 3, 6, 1, 2, 5]
    @test byfirst == ps[perm]
    withskip = Pipelines.counting_sort!(similar(ps, 8), ps, by = first, skip = 1)
    @test withskip[2:end] == ps[perm]

    bylast = Pipelines.counting_sort!(similar(ps), ps, by = last)
    @test bylast == ps[sortperm(last.(ps))]
end
