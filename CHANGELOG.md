# Changelog

## Version 2.0.0

### Major breaking changes

- A repository reserves tables of the form `_table_{number}` and views of the form `_view_{number}` [#98](https://github.com/LimenResearch/DashiBoard/pull/98).
- Dropped support for `keep_vars` in `evaljoin` and `train_evaljoin!` [#99](https://github.com/LimenResearch/DashiBoard/pull/99).
- `evaljoin` and `train_evaljoin!` now take a mandatory argument `id_var` denoting a column with _unique_ entries present in the data, to be used to join with the output [#100](https://github.com/LimenResearch/DashiBoard/pull/100).
- `WildCard` no longer accepts `_train` and `_eval` functions as type parameters [#101](https://github.com/LimenResearch/DashiBoard/pull/101).
- Nodes inverted with `invert` have automatically `train = false` and can no longer be inverted back [#107](https://github.com/LimenResearch/DashiBoard/pull/107).
- `Pipelines.get_inputs` and `Pipelines.get_outputs` now work directly on nodes, not on cards [#110](https://github.com/LimenResearch/DashiBoard/pull/110).
- `Pipelines.get_inputs` and `Pipelines.get_outputs` are renamed to `Pipelines.get_node_inputs` and `Pipelines.get_node_outputs` [#117](https://github.com/LimenResearch/DashiBoard/pull/117).
- `SourceVariables` and `OutputVariables` are used to specify how a card uses table variables [#117](https://github.com/LimenResearch/DashiBoard/pull/117).
- `CardConfig` was simplified and renamed to `CardSpec` [#120](https://github.com/LimenResearch/DashiBoard/pull/120).
- `Pipelines.get_metadata` and `Pipelines.card_widgets` are still public no longer exported [#122](https://github.com/LimenResearch/DashiBoard/pull/122).
- `register_wild_card` and `WildCardSettings` are the preferred way to register a wild card [#123](https://github.com/LimenResearch/DashiBoard/pull/123).
- The API `"method": "m"` + `"method_options": {"opt1": v1, "opt2": v2}` configuration in Pipelines is superseded by `method: {"type": "m", "opt1": v1, "opt2": v2}`. In the StreamlinerCard, the same change occurred for `model` and `training`, and the data `funnel` has now to be passed explicitly in the same way [#143](https://github.com/LimenResearch/DashiBoard/pull/143).
- In Pipelines, the dot notation for `method_options`, e.g., `"method_options.kmeans.n_classes": 7`, is no longer supported [#143](https://github.com/LimenResearch/DashiBoard/pull/143).
- When loading several files, the filename is no longer added by default as a new `_name` column, pass `filename = "_name"` to recover the old behavior [#149](https://github.com/LimenResearch/DashiBoard/pull/149).
- `DuckDBUtils.to_sql` now defaults to `duckdb` dialect [#151](https://github.com/LimenResearch/DashiBoard/pull/151).
- In `DataIngestion.load_files`, `union_by_name` now respect DuckDB default (i.e., `false`) [#151](https://github.com/LimenResearch/DashiBoard/pull/151).

### Features

- Mixed model support [#83](https://github.com/LimenResearch/DashiBoard/pull/83).
- Support for Gaussian encoding of week day [#86](https://github.com/LimenResearch/DashiBoard/pull/86).
- Training and evaluation now support callbacks [#99](https://github.com/LimenResearch/DashiBoard/pull/99).
- Support transformation in `DataIngestion.select` [#104](https://github.com/LimenResearch/DashiBoard/pull/104).
- `DataIngestion.load_files` supports loading data as a view [#151](https://github.com/LimenResearch/DashiBoard/pull/151).
