## Variational Auto Encoder

struct VAESpec
    embedding::Vector{Any}
    model::Vector{Any}
    projection::Vector{Any}
end

function vae_forward(modules, x)
    (; embedding, model_μ, model_logvar, projection) = modules
    y = embedding(x.input)
    μ, logvar = model_μ(y), model_logvar(y)
    σ = @. exp(logvar / 2)
    ϵ = randn_like(σ)
    z = @. ϵ * σ + μ
    prediction = projection(z)
    return merge(x, (; prediction, μ, logvar))
end

function instantiate(v::VAESpec, templates)
    input = Shape(templates.input)
    output = Shape(templates.input)

    sh_m = requires_shape(first(v.model))
    sh_p = requires_shape(first(v.projection))

    embedding, sh = chain(v.embedding, input, sh_m)

    model_μ, _ = chain(v.model, sh, sh_p)
    model_logvar, sh = chain(v.model, sh, sh_p)

    projection, _ = chain(v.projection, sh, output)

    modules = (; embedding, model_μ, model_logvar, projection)

    return Architecture(:VAE, vae_forward, modules)
end

vae(components::AbstractDict) = architecture(VAESpec, components)

# loss

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
