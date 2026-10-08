# StreamlinerCore

```@meta
CurrentModule = StreamlinerCore
```

StreamlinerCore is a julia library to generate, train and evaluate models
defined via some configuration files.

## Data interface

```@docs
StreamlinerCore.AbstractData
StreamlinerCore.stream
StreamlinerCore.ingest
StreamlinerCore.get_templates
StreamlinerCore.get_metadata
StreamlinerCore.get_nsamples
StreamlinerCore.Template
```

## Funnels

A funnel decides which rows and columns a model is fed. Its schema and its construction from a
document both come from its fields; a funnel that wraps another is written flat, the wrapped
funnel's fields beside its own.

```@docs
StreamlinerCore.DBFunnel
StreamlinerCore.funnel_IR
StreamlinerCore.make_funnel
StreamlinerCore.flat_IR
StreamlinerCore.split_config
StreamlinerCore.TransformError
StreamlinerCore.output_fields
```

## Parser

```@docs
StreamlinerCore.Parser
StreamlinerCore.default_parser
```

## Parsed objects

```@docs
StreamlinerCore.Model
StreamlinerCore.Training
StreamlinerCore.Streaming
```

## Training and evaluation

```@docs
Result
has_weights
train
finetune
loadmodel
validate
evaluate
summarize
```
