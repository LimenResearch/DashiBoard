# Pipelines

```@meta
CurrentModule = Pipelines
```

Pipelines is a library designed to generate and evaluate data analysis pipelines.

## Transformation interface

```@docs
Pipelines.Card
Pipelines.Card(::AbstractDict)
Pipelines.Card(::AbstractDict, ::AbstractDict)
Pipelines.train
Pipelines.evaluate
Pipelines.get_node_inputs
Pipelines.get_node_outputs
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
Pipelines.WindowFunctionCard
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

## Cluster reconciliation

The cluster card's evaluation refits on its stored members plus the unseen
rows and reconciles the two clusterings following MONIC's transition model;
`_relabel_map` is the reconciliation engine — internal, but the semantics of
cluster identity evolution live there.

```@docs
Pipelines._relabel_map
```

## Card registration

```@docs
Pipelines.register_card
Pipelines.CardSpec
```
