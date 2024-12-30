@testset "train" begin
    mktempdir() do prefix
        test_mnist_conv(prefix)
        test_optim(prefix)
        test_vae(prefix)
    end
end
