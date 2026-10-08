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

## What a card writes

A card says what it writes with `output_spec`: a list of groups, each named when the card writes
more than one thing. A group that derives its columns from those the card was given
(`VariableTransformSpec`) is one a `through` chain can pass a value through; one that writes names
of its own (`OutputSpec`) is not.

```@docs
Pipelines.output_spec
Pipelines.OutputGroup
Pipelines.OutputSpec
Pipelines.VariableTransformSpec
Pipelines.products
Pipelines.selected_products
Pipelines.product_groups
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

## Card registration

```@docs
Pipelines.register_card
Pipelines.CardSpec
```
