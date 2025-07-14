## Wild card

struct WildCard{T, E} <: StandardCard
    train::T
    evaluate::E
    columns::Vector{String}
    partition::Union{String, Nothing}
    outputs::Vector{String}
end

partition(wc::WildCard) = wc.partition
columns(wc::WildCard) = wc.columns
outputs(wc::WildCard) = wc.outputs

_train(wc::WildCard, t) = wc.train(t)
(wc::WildCard)(t) = wc.evaluate(t)
