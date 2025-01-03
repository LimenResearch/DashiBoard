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
StreamlinerCore.get_summary
StreamlinerCore.get_nsamples
StreamlinerCore.Template
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
train
finetune
loadmodel
validate
evaluate
summarize
```

## Utilities

```@docs
StreamlinerCore.has_weights
```
