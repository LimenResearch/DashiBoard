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
with_table
in_schema
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
```