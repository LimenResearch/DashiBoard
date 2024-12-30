# Set up registry

@info "Initializing registry."
registry = Registry("mongodb://localhost:27017", "test-database", "registry")

# Clean up registry if it already exists
@info "Destroying all entries in registry."
open(drop, registry)

@testset "train" begin
    mktempdir() do prefix
        test_mnist_conv(prefix)
        test_optim(prefix)
        test_vae(prefix)
    end
end

# test registry utils

@testset "replace prefix" begin
    N = open(length, registry)
    @test N > 0

    res = StreamlinerCore.replace_prefix(registry, "prefix")
    @test res["modifiedCount"] == N
    @test res["matchedCount"] == N
    @test res["upsertedCount"] == 0

    for entry in open(collect, registry)
        @test entry["result"]["prefix"] == "prefix"
    end

    res = StreamlinerCore.replace_prefix(registry, "prfix" => "updated/prefix")
    @test res["modifiedCount"] == 0
    @test res["matchedCount"] == 0
    @test res["upsertedCount"] == 0

    for entry in open(collect, registry)
        @test entry["result"]["prefix"] == "prefix"
    end

    res = StreamlinerCore.replace_prefix(registry, "prefix" => "updated/prefix")
    @test res["modifiedCount"] == N
    @test res["matchedCount"] == N
    @test res["upsertedCount"] == 0

    for entry in open(collect, registry)
        @test entry["result"]["prefix"] == "updated/prefix"
    end
end

# Clean up registry after training

@info "Destroying all entries in registry."
open(drop, registry)
