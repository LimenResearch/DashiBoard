to_pair(s::AbstractString) = s => s
to_pair(s::Pair) = s

function train_many!(
        repository::Repository, nodes::Union{Tuple, AbstractVector},
        table::AbstractString; schema = nothing
    )
    n = length(nodes)
    Threads.@threads for i in 1:n
        train!(repository, nodes[i], table; schema)
    end
    return
end

function evaljoin_many(
        repository::Repository, nodes::Union{Tuple, AbstractVector},
        table_names::Union{AbstractString, Pair}; schema = nothing
    )
    n = length(nodes)
    outputs = get_outputs.(nodes)
    tmp_names = join_names.(string(uuid4()), 1:n)
    id_vars = new_name.("id", outputs)
    (source, destination) = to_pair(table_names)

    try
        Threads.@threads for i in 1:n
            evaluate(repository, nodes[i], source => tmp_names[i], id_vars[i]; schema)
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

function train_evaljoin_many!(
        repository::Repository, nodes::Union{Tuple, AbstractVector},
        table_names::Union{AbstractString, Pair}; schema = nothing
    )
    (source, destination) = to_pair(table_names)
    train_many!(repository, nodes, source; schema)
    evaljoin_many(repository, nodes, source => destination; schema)
    return
end
