## Variational Auto Encoder

@kwdef struct VAE{E, M, L, P}
    embedding::E
    model_μ::M
    model_logvar::L
    projection::P
end

@layer VAE

function (v::VAE)(x)
    y = v.embedding(x.input)
    μ, logvar = v.model_μ(y), v.model_logvar(y)
    σ = @. exp(logvar / 2)
    ϵ = randn_like(σ)
    z = @. ϵ * σ + μ
    prediction = v.projection(z)
    return merge(x, (; prediction, μ, logvar))
end

@kwdef struct VAELoss{A, B <: Real}
    agg::A = mean
    beta::B = 1
end

# TODO this loss is extremely basic. It should be improved, e.g., regularization
function (v::VAELoss)(r)
    (; agg, beta) = v
    (; input, prediction, μ, logvar) = r
    N = ndims(μ)
    β::eltype(input) = beta # convert to matching float type
    rec = Flux.mse(prediction, input; agg)
    gkld = @. (exp(logvar) + μ^2 - 1 - logvar) / 2
    kld = agg(sum(gkld, dims = 1:(N - 1)))
    return rec + β * kld
end

metricname(::VAELoss) = :vae_loss

# constructor

struct VAESpec
    embedding::Vector{Any}
    model::Vector{Any}
    projection::Vector{Any}
end

function instantiate(v::VAESpec, templates)
    input = Shape(templates.input)
    output = Shape(templates.input)

    embedding, sh = chain(v.embedding, input)

    model_μ, _ = chain(v.model, sh)
    model_logvar, sh = chain(v.model, sh)

    projection, _ = chain(v.projection, sh, output)

    return VAE(; embedding, model_μ, model_logvar, projection)
end

vae(components::Config) = architecture(VAESpec, components)
