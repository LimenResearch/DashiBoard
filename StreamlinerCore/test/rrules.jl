@testset "L1 derivative" begin
    test_rrule(StreamlinerCore._l1, rand(3))
    test_rrule(StreamlinerCore._l1, zeros(3))
    test_rrule(StreamlinerCore._l1, rand(ComplexF64, 3))
    test_rrule(StreamlinerCore._l1, zeros(ComplexF64, 3))
end
