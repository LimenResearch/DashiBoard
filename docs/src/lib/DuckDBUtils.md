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
drain_connections!
with_appender
with_connection
with_table_name
with_table_names
render_params
to_sql
```

## Table tools

```@docs
initialize_table
load_table
replace_table
export_table
delete_table
with_table
with_view
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
