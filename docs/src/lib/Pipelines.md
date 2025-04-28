# Pipelines

```@meta
CurrentModule = Pipelines
```

Pipelines is a library designed to generate and evaluate data analysis pipelines.

## Transformation interface

```@docs
Pipelines.AbstractCard
Pipelines.train
Pipelines.evaluate
Pipelines.inputs
Pipelines.outputs
Pipelines.invertible
```

## Pipeline computation

```@docs
Pipelines.get_card
Pipelines.evaluate(repository::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)
```

## Pipeline visualization

```@docs
Pipelines.visualize
```

## Cards

```@docs
Pipelines.SplitCard
Pipelines.RescaleCard
Pipelines.ClusterCard
Pipelines.DimensionalityReductionCard
Pipelines.GLMCard
Pipelines.InterpCard
Pipelines.GaussianEncodingCard
Pipelines.StreamlinerCard
```