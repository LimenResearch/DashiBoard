# DataIngestion

```@meta
CurrentModule = DataIngestion
```

## Ingestion interface

```@docs
DataIngestion.is_supported
DataIngestion.acceptable_paths
DataIngestion.load_files
```

### Internal

```@docs
DataIngestion.parse_paths
```

## Metadata for filter generation

```@docs
DataIngestion.summarize
```

## Filtering interface

```@docs
DataIngestion.Filter
DataIngestion.Filter(c::AbstractDict)
DataIngestion.select
```

## Filters

```@docs
DataIngestion.IntervalFilter
DataIngestion.ListFilter
```
