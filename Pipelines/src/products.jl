# Several products from one card.
#
# A card may write more than one thing from the same columns — a prediction and its uncertainty,
# say. That is not a property of any one card: a card opts in by declaring its `products`, carrying
# a `select` field, and building its groups with `product_groups`. The naming rule and what a
# selection may be are decided here, once.

"""
    ProductError(message, field, pointer = nothing)

A card asked for products it cannot write. `field` is the field of the card at fault — `select` or
`suffix` — and `pointer` addresses it in the document; that is known where the document is walked
rather than where the selection is checked, so it is filled in there. With both, a form can mark
the control instead of showing a sentence with nowhere to go.
"""
struct ProductError <: Exception
    message::String
    field::String
    pointer::Maybe{String}
end

ProductError(message::AbstractString, field::AbstractString) = ProductError(message, field, nothing)

Base.showerror(io::IO, err::ProductError) = print(io, err.message)

"""
    products(card)::Vector{String}

The products `card` can write, in the order it declares them. The first is the one its `suffix`
names. Empty for a card with a single, unnamed product — every card that does not opt in.
"""
products(::Card) = String[]

"""
    selected_products(card)::Vector{String}

The products to write: what the author selected, or every one when nothing was said.
"""
selected_products(card::Card) = something(card.select, products(card))

"""
    product_suffixes(select, all, suffix)::Vector{String}

The suffix each selected product is written under: `suffix` for the first of `all`, its own name
for any other.
"""
function product_suffixes(select::AbstractVector, all::AbstractVector, suffix::AbstractString)
    isempty(select) && throw(ProductError("`select` names no product; leave it out to write them all", "select"))
    allunique(select) || throw(ProductError("`select` names a product more than once", "select"))
    unknown = setdiff(select, all)
    isempty(unknown) || throw(
        ProductError("`select` names $(join(unknown, ", ")), which is not among $(join(all, ", "))", "select")
    )
    suffixes = String[product == first(all) ? suffix : product for product in select]
    allunique(suffixes) || throw(
        ProductError(
            "`suffix` is \"$(suffix)\", which is also the name of a selected product: both would write the same columns",
            "suffix"
        )
    )
    return suffixes
end

"""
    product_groups(cols, select, all, suffix)::Vector{OutputGroup}

One named group per selected product, each a transform of `cols`. Always named, even when one is
selected, so a chain can ask for a product by name before a second is ever chosen.
"""
function product_groups(
        cols::AbstractVector, select::AbstractVector, all::AbstractVector, suffix::AbstractString
    )
    suffixes = product_suffixes(select, all, suffix)
    return [OutputGroup(product, VariableTransformSpec(cols, s)) for (product, s) in zip(select, suffixes)]
end

"""
    select_IR(products)

The schema of a `select` field over fixed `products`. Its default is the whole list, which is
what an absent `select` means, so a form shows every product chosen without knowing the rule.
"""
function select_IR(products::AbstractVector{<:AbstractString})
    # A product is written once, so the list is a set.
    return ArrayIR{String}(items = StringIR(enum = products), minItems = 1, default = collect(String, products), uniqueItems = true)
end
