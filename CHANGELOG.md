# Changelog

## Unreleased

### Major breaking changes

- A streamliner funnel lists its columns by name and gives transforms in separate maps, `input_transforms` and `target_transforms`, keyed by column; `{colname, transform}` objects are no longer accepted. A funnel document is checked against its schema: an unknown key is refused, and `inputs` and `targets` are required.
- The transform registry no longer has a `""` entry: a column without an entry in its map is taken as it is. `log`, `log1p`, `sqrt` and `asinh` are registered beside `identity`.
- A `through` chain that passes a value through a node that cannot carry it is refused with a `ThroughError` pointing at the card or group that holds the chain.
- `DashiBoard.launch(workspace; data_dir, pipeline_dir, filter_dir, model_dir, training_dir, ...)` replaces `launch(data_directory; model_directory, training_directory, ...)`. `bin/launch.jl` takes a workspace folder and the flags `--data_dir`, `--pipeline_dir`, `--filter_dir`, `--model_dir` and `--training_dir`, replacing the positional data directory, `--model_directory` and `--training_directory`. A directory is resolved from its flag, then the workspace's `dashiboard.toml`, then its conventional folder, then the workspace root; `static/model` and `static/training` are no longer defaults.
- `list-files` answers `{files, misplaced, folders}` instead of a bare list of files.
- `read-document` and `write-document` take paths relative to the workspace instead of the data directory; `write-document` and `write-configuration` refuse hidden paths and `dashiboard.toml`.
- A card declares what it writes with `output_spec(card)`, returning a list of `OutputGroup`s (each an `OutputSpec`, or a `VariableTransformSpec` for outputs derived from given columns); `OutputVariables(card)` is no longer called.

### Features

- A card can write several named products; the streamliner card writes every field its model yields, or the ones named in `select`.
- A `through` step or a `nodes` selection can keep only some of a node's products: `{node, products}` in a chain, `{nodes, products}` on a selector item. The probe reports each node's products and how a value may pass through it.
- A streamliner funnel's schema comes from the funnel's own fields, so the form can build a streamliner card; a funnel that wraps another is written flat (`flat_IR`, `split_config`). The probe reports the columns a funnel's lists resolve to.
- The probe and a run check that each streamliner model can be built for its funnel, and report one that cannot at the card's `model` (`Pipelines.model_issue`).
- A streamliner card that kept no trained model says why at prediction — never trained, or no validation rows because it has no `partition`.
- The server runs against a workspace: `dashiboard.toml` with `[directories]`, `[extensions]` and `[server]`; `bin/launch.jl --init` sorts a plain folder into the layout; the launcher starts the server in an environment holding the workspace's extensions.
- Routes to read and write each kind of file (`read-pipeline`, `write-pipeline`, `read-filters`, `write-filters`, `read-model`, `write-model`, `read-training`, `write-training`), to list, read and write model and training configurations (`list-configurations`, `read-configuration`, `write-configuration`), and to download a pipeline with the configurations and extensions it names as a zip (`bundle-pipeline`).
- DashiBase: `EitherIR` for a value of one of several types, `MapIR` for a map of names to values of one kind, and `uniqueItems` on `ArrayIR` for a list that is a set.

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
- `DataIngestion.summarize` only returns `min` and `max` for numerical columns, and it no longer returns a suggested `step` for a slider widget [#150](https://github.com/LimenResearch/DashiBoard/pull/150).
- `DuckDBUtils.to_sql` now defaults to `duckdb` dialect [#151](https://github.com/LimenResearch/DashiBoard/pull/151).
- In `DataIngestion.load_files`, `union_by_name` now respect DuckDB default (i.e., `false`) [#151](https://github.com/LimenResearch/DashiBoard/pull/151).

### Features

- Mixed model support [#83](https://github.com/LimenResearch/DashiBoard/pull/83).
- Support for Gaussian encoding of week day [#86](https://github.com/LimenResearch/DashiBoard/pull/86).
- Training and evaluation now support callbacks [#99](https://github.com/LimenResearch/DashiBoard/pull/99).
- Support transformation in `DataIngestion.select` [#104](https://github.com/LimenResearch/DashiBoard/pull/104).
- New `DuckDBUtils.execute_with_macros` function to temporarily register SQL macros before executing a query [#150](https://github.com/LimenResearch/DashiBoard/pull/150).
- `DataIngestion.load_files` supports loading data as a view [#151](https://github.com/LimenResearch/DashiBoard/pull/151).
