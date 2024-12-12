# DuckDBUtils

```@meta
CurrentModule = DuckDBUtils
```

## Database interface

```@docs
Repository
get_catalog
acquire_connection
release_connection
with_connection
render_params
```

## Table tools

```@docs
with_table
colnames
```

## Batched iteration

```@docs
Batches
```

## Internal functions

```@docs
DuckDBUtils._numobs
DuckDBUtils._init
DuckDBUtils._append!
DuckDBUtils.in_schema
```