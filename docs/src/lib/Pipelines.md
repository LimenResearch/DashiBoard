# Pipelines

```@meta
CurrentModule = Pipelines
```

Pipelines is a library designed to generate and evaluate data analysis pipelines.

## Transformation interface

```@docs
Pipelines.Card
Pipelines.train
Pipelines.evaluate
Pipelines.get_inputs
Pipelines.get_outputs
Pipelines.invertible
```

## Pipeline computation

```@docs
Pipelines.Node
Pipelines.train!
Pipelines.evaljoin
Pipelines.train_evaljoin!
```

## Pipeline reports

```@docs
Pipelines.report
```

## Pipeline visualizations

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
Pipelines.MixedModelCard
Pipelines.InterpCard
Pipelines.GaussianEncodingCard
Pipelines.StreamlinerCard
Pipelines.WildCard
```

## Card registration

```@docs
Pipelines.register_card
Pipelines.CardConfig
```
