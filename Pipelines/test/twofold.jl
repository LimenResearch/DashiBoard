using Pipelines: @kwarg

# A card that is not a streamliner, opting in to several products with the same three steps a
# streamliner uses: declare them, carry `select`, build the groups with `product_groups`.
@kwarg struct TwofoldCard <: Pipelines.StandardCard
    inputs::Vector{String} & (dashi = Pipelines.VARIABLES_DEF,)
    suffix::String = "double"
    select::Union{Vector{String}, Nothing} = nothing & (dashi = Pipelines.select_IR(["double", "triple"]),)
end

Pipelines.products(::TwofoldCard) = ["double", "triple"]
Pipelines.SourceVariables(c::TwofoldCard) = Pipelines.SourceVariables(; c.inputs)
Pipelines.output_spec(c::TwofoldCard) = Pipelines.product_groups(
    c.inputs, Pipelines.selected_products(c), Pipelines.products(c), c.suffix
)
Pipelines._train(::TwofoldCard, t, id_var) = nothing
function (c::TwofoldCard)(_, t, id_var)
    select = Pipelines.selected_products(c)
    suffixes = Pipelines.product_suffixes(select, Pipelines.products(c), c.suffix)
    factor = Dict("double" => 2, "triple" => 3)
    out = Pipelines.SimpleTable(id_var => t[id_var])
    for (product, suffix) in zip(select, suffixes), col in c.inputs
        out[string(col, "_", suffix)] = factor[product] .* t[col]
    end
    return out
end
Pipelines.register_card("twofold" => Pipelines.CardSpec(TwofoldCard, "Twofold"))
