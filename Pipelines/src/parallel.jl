function train_many(
        repository::Repository, cards::AbstractVector,
        source::AbstractString; schema = nothing
    )::Vector{CardState}
    Base.require_one_based_indexing(cards)
    n = length(cards)
    states = similar(Vector{CardState}, n)
    Threads.@threads for i in 1:n
        states[i] = train(repository, cards[i], source; schema)
    end
    return states
end

function evaluate_many(
        repository::Repository, cards::AbstractVector,
        (source, destination)::Pair; schema = nothing
    )
    states = train_many(repository, cards, source; schema)
    evaluate_many(repository, cards, states, source => destination; schema)
    return states
end

function evaluate_many(
        repository::Repository, cards::AbstractVector, states::AbstractVector,
        (source, destination)::Pair; schema = nothing, invert = false
    )
    Base.require_one_based_indexing(cards)
    Base.require_one_based_indexing(states)
    n = length(cards)

    inputs, outputs = if invert
        get_inverse_inputs.(cards), get_inverse_outputs.(cards)
    else
        get_inputs.(cards), get_outputs.(cards)
    end
    tmp_names = join_names.(string(uuid4()), 1:n)
    id_vars = new_name.("id", inputs, outputs)

    try
        Threads.@threads for i in 1:n
            if invert
                evaluate(repository, cards[i], states[i], source => tmp_names[i], id_vars[i]; schema, invert)
            else
                evaluate(repository, cards[i], states[i], source => tmp_names[i], id_vars[i]; schema)
            end
        end
        q = join_on_row_number(source, tmp_names, id_vars, outputs)
        replace_table(repository, q, destination; schema)
    finally
        for tmp in tmp_names
            delete_table(repository, tmp; schema)
        end
    end
    return
end
