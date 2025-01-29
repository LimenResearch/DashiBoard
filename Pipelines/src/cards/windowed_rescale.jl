"""
    struct WindowedRescaleCard <: AbstractCard

Defines a card for applying rescaling methods over a rolling window to timeseries data.

Fields:
- `method::String`: Rescaling method (`zscore`, `maxabs`, `minmax`).
- `columns::Vector{String}`: Columns to rescale.
- `window_type::String`: Window type (`index` or `time`).
- `window_size::Union{Int, String}`: Window size:
    - For `window_type="index"`, this is the number of rows.
    - For `window_type="time"`, this is a time period (e.g., "24 hours").
- `sorters::Vector{String} = String[]`: Timestamp column for time-based windows.
- `by::Vector{String}`: Optional grouping keys.
- `suffix::String`: Suffix added to output column names.

Notes:
- Only the following methods are supported: `zscore`, `maxabs`, `minmax`.
- For `window_type="time"`, `sorters` must be specified.
"""
@kwdef struct WindowedRescaleCard <: AbstractCard
    method::String
    columns::Vector{String}
    window_type::String
    window_size::Union{Int, String}
    sorters::Vector{String} = String[]
    by::Vector{String} = String[]
    suffix::String = "windowed"
    idx_uid::String = string(uuid4())
    function WindowedRescaleCard(method, columns, window_type, window_size, sorters = nothing, by = String[], suffix = "windowed", idx_uid = string(uuid4()))
        # Validate method
        !(method in keys(RESCALERS)) && throw(ArgumentError("Invalid `method`. Supported methods are: zscore, maxabs, minmax."))
        isempty(RESCALERS[method].stats) && throw(ArgumentError("Method `$method` is not supported for windowing."))
        # Validate window type
        !(window_type in ["index", "time"]) && throw(ArgumentError("Invalid `window_type`. Must be 'index' or 'time'."))
        window_type == "time" && ismissing(sorters) && throw(ArgumentError("`sorters` must be provided for `window_type='time'."))
        window_type == "index" && !(window_size isa Int) && throw(ArgumentError("`window_size` must be an integer for `window_type='index'."))
        new(method, columns, window_type, window_size, sorters, by, suffix, idx_uid)
    end
end

function init_source(source, sorters, by, idx_uid)
    return From(source) |>
        Partition(
        order_by = Get.(sorters),
        by = Get.(by)
    ) |>
        Define(idx_uid => Agg.row_number())
end

function partition_source(idx_uid, by, window_size)
    return Partition(
        ; order_by = [Symbol(idx_uid)],
        by = getindex.(Get, by),
        frame = (mode = :range, start = -window_size, finish = -1)
    )
end

function Pipelines.train(
        repo::Repository,
        card::WindowedRescaleCard,
        source::AbstractString;
        schema = nothing
    )
    (; columns, method, window_size, sorters, by, idx_uid) = card
    (; stats) = RESCALERS[method]


    # Create `_indices` column and compute aggregates
    aggregate_selects = [
        Symbol(col, "_", stat_name) => stat_function(Get(Symbol(col)))
            for col in columns for (stat_name, stat_function) in stats
    ]

    init_query = init_source(source, sorters, by, idx_uid)
    partition_query = partition_source(idx_uid, by, window_size)
    q = init_query |>
        partition_query |> 
        Select(
            Symbol(idx_uid),
            getindex.(Get, by)...,  # Include grouping keys
            aggregate_selects...  # Compute aggregates
        ) |>
        Where(Fun(">", Get(Symbol(idx_uid)), window_size))

    return DBInterface.execute(fromtable, repo, q; schema = schema)
end

function Pipelines.evaluate(
        repo::Repository,
        card::WindowedRescaleCard,
        stats_tbl::SimpleTable,
        (source, target)::Pair;
        schema = nothing
    )
    (; columns, method, suffix, sorters, window_size, by, idx_uid) = card
    (; transform) = RESCALERS[method]

    available_columns = colnames(repo, source; schema)
    transformed = [string(c, '_', suffix) => transform(c) for c in columns if c in available_columns]
    target_columns = union(available_columns, first.(transformed))
    join_cols = union(by, [idx_uid])
    eqs = (.==).(Get.(join_cols), GetStats.(join_cols))
    init_query = init_source(source, sorters, by, idx_uid)
    partition_query = partition_source(idx_uid, by, window_size)

    return with_table(repo, stats_tbl; schema) do tbl_name
        q = init_query |>
            partition_query |>
            Define(:_indices => Agg.row_number()) |>  # Regenerate `_indices` to join
            Join("stats" => From(tbl_name), on = Fun.and(eqs...)) |>
            Define(transformed...) |> # Apply transformations using stats
            Select(Get.(target_columns)...)
        replace_table(repo, q, target; schema)
    end
end