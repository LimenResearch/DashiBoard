@testset "train" begin
    mktempdir() do outputdir
        test_mnist_conv(outputdir)
        test_optim(outputdir)
        test_vae(outputdir)
    end
end
