# Changelog

## Version 2.0.0

### Major breaking changes

- A repository reserves tables of the form `_table_{number}` and views of the form `_view_{number}` [#98](https://github.com/LimenResearch/DashiBoard/pull/98).
- Dropped support for `keep_vars` in `evaljoin` and `train_evaljoin!` [#99](https://github.com/LimenResearch/DashiBoard/pull/99).
- `evaljoin` and `train_evaljoin!` now take a mandatory argument `id_var` denoting a column with _unique_ entries present in the data, to be used to join with the output [#100](https://github.com/LimenResearch/DashiBoard/pull/100).

### Features

- Mixed model support [#83](https://github.com/LimenResearch/DashiBoard/pull/83).
- Support for Gaussian encoding of week day [#86](https://github.com/LimenResearch/DashiBoard/pull/86).
- Training and evaluation now support callbacks [#99](https://github.com/LimenResearch/DashiBoard/pull/99).
- Support transformation in `DataIngestion.select` [#104](https://github.com/LimenResearch/DashiBoard/pull/104).
- `DuckDBUtils.render_params` now can also accepts a `Repository` instead of a `SQLCatalog` [#106](https://github.com/LimenResearch/DashiBoard/pull/106).