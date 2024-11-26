# DataIngestion

```@meta
CurrentModule = DataIngestion
```

## Database interface

```@docs
Repository
```

## Ingestion interface

```@docs
DataIngestion.is_supported
DataIngestion.load_files
```

## Selection interface

```@docs
Filters
DataIngestion.select
```

## Filters

```@docs
DataIngestion.IntervalFilter
DataIngestion.ListFilter
```

### Metadata for filter generation

```@docs
DataIngestion.summarize
```