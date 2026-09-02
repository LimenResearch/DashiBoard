# General utils

map_into(f::F, ::Type{T}, x) where {F, T} = (y::T = T(x); map!(f, values(y)); y)

to_stringlist(s::Maybe{AbstractString}) = isnothing(s) ? String[] : String[s]
to_stringlist(s::AbstractVector) = convert(Vector{String}, s)

function to_maybestring(s::AbstractVector)::Maybe{String}
    return isempty(s) ? nothing : only(s)
end

to_maybestring(s::Maybe{AbstractString})::Maybe{String} = s

# Card computation utils

select_columns(args...) = Select(args = Get.(union(args...)))

sort_columns(cols::AbstractVector) = Order(by = Get.(cols))

filter_training(partition::AbstractString) = Where(Get(partition) .== 1)
filter_training(::Nothing) = Where(Lit(true)) # without partition, everything goes in training

# Prediction utils

_predict(m::RegressionModel, X::AbstractMatrix) = predict(m, X)

_predict(m::MDS, X::AbstractMatrix) = stack(Fix1(vec ∘ predict, m), eachcol(X))

# Multithreading utils

putmany!(ch::Channel, iter) = foreach(Fix1(put!, ch), iter)

function to_channel(iter)
    n = length(iter)
    T = eltype(iter)
    return Channel{T}(ch -> putmany!(ch, iter), n, spawn = true)
end

# graph utils

function digraph(src::AbstractVector{I}, tgt::AbstractVector{I}, N::Integer) where {I <: Integer}
    edges::Vector{Edge{I}} = Edge{I}.(src, tgt)
    # create graph and manually add potentially missing vertices
    G = DiGraph(edges)
    add_vertices!(G, N - nv(G))
    return G
end
