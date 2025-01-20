"""
    struct GaussianCard <: AbstractCard

Defines a card for Gaussian transformations of a specified column.

Fields:
- `column::String`: The name of the column to transform.
- `means::Int`: The number of means (Gaussian distributions) to generate.
- `max::Float64`: The maximum value used for normalization (denominator).
- `coef::Float64`: A coefficient for scaling the standard deviation.
- `suffix::String`: A suffix added to the output column names.
"""
@kwdef struct GaussianCard <: AbstractCard
    column::String
    means::Int
    max::Float64
    coef::Float64  = 0.5
    suffix::String = "gaussian"
end

inputs(g::GaussianCard) = [g.column, g.means, g.max, g.coef]

outputs(g::GaussianCard) = [string(g.column, "_", g.suffix, "_", i) for i in 1:g.means]

"""
train(repo::Repository, g::GaussianCard; schema=nothing) -> SimpleTable

Generates a SimpleTable containing:
- `sigma`: The standard deviation for the Gaussian transformations.
- `denominator`: The normalization value.
- `mean_1, mean_2, ..., mean_n`: Columns for each Gaussian mean.

The means are evenly spaced in the range [0, 1].

Args:
- `repo`: The repository instance (not used but included for consistency).
- `g`: The GaussianCard instance.
- `schema`: Optional schema name.

Returns:
- A SimpleTable (Dict{String, AbstractVector}) containing Gaussian parameters.
"""
function train(repo::Repository, g::GaussianCard; schema = nothing)
    μs = range(0, stop=1, length=g.means)  # Means normalized between 0 and 1
    σ = round(step(μs) * g.coef, digits=4)

    # Create a SimpleTable
    stats = Dict(
        "sigma" => [σ],  # Standard deviation
        "denominator" => [g.max]  # Normalization value
    )
    for (i, μ) in enumerate(μs)
        stats["mean_$i"] = [μ]  # Add each mean as a separate key
    end
    return SimpleTable(stats)
end

"""
gaussian_transform(x, μ, σ, d) -> Float64

Applies the Gaussian transformation:
    exp(- ((x / d) - μ)^2 / σ)

Args:
- `x`: The input value to transform.
- `μ`: The Gaussian mean.
- `σ`: The standard deviation.
- `d`: The normalization denominator.

Returns:
- The transformed value as a Float64.
"""
gaussian_transform(x, μ, σ, d) = @. exp(- ((x / d) - μ) * ((x / d) - μ) / σ)


"""
evaluate(repo::Repository, g::GaussianCard, stats_tbl::SimpleTable, (source, target)::Pair; schema=nothing)

Evaluates the Gaussian transformation defined by the GaussianCard and applies it to the source table.

Args:
- `repo`: The repository instance.
- `g`: The GaussianCard instance.
- `stats_tbl`: A SimpleTable containing the Gaussian parameters.
- `source`: The source table name.
- `target`: The target table name.
- `schema`: Optional schema name.

This function:
1. Temporarily registers the stats table using `with_table`.
2. Joins the source table with the stats table using a CROSS JOIN.
3. Carries over all columns from the source table.
4. Generates new columns (`gaussian_1`, `gaussian_2`, ...) for the transformed values.
5. Replaces the target table with the results.
"""
function evaluate(
    repo::Repository, g::GaussianCard, stats_tbl::SimpleTable, (source, target)::Pair; schema = nothing
)
    # Generate transformed column expressions for each Gaussian
    converted = [
        string(g.column, "_", g.suffix, "_", i) => gaussian_transform(
            Get(g.column),  # Input column
            Get(Symbol("mean_$i")),  # Gaussian mean column
            Get(:sigma),  # Sigma column
            Get(:denominator)  # Denominator column
        )
        for i in 1:g.means
    ]

    # Use with_table to temporarily register the stats table
    with_table(repo, stats_tbl; schema) do tbl_name
        # Construct the query to join stats and carry over all source columns
        query = From(source) |>
            Join(From(tbl_name), on = true) |>  # CROSS JOIN
            Define(converted...)  # Add transformed columns while keeping the original ones

        # Replace the target table with the results
        replace_table(repo, query, target; schema)
    end
end
