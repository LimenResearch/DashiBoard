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
```

## Pipeline computation

```@docs
Pipelines.get_card
Pipelines.evaluate(repo::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)
```

## Cards

```@docs
Pipelines.RescaleCard
Pipelines.SplitCard
Pipelines.GLMCard
Pipelines.InterpCard
Pipelines.GaussianEncodingCard
```