# Getting Started

DashiBoard is still in development, thus installing requires a few passages.

## Installation dependencies

- Julia programming language (minimum version 1.11, installable via [juliaup](https://github.com/JuliaLang/juliaup)).
- JavaScript package manager [pnpm](https://pnpm.io/).

## Launching the server

Open a terminal at the top-level of the repository.

Install all required dependencies with the following command:

```
julia --project=DashiBoard -e 'using Pkg; Pkg.instantiate()'
```

Then, launch the server with the following command:

```
julia --project=DashiBoard -e 'using DashiBoard; ws = "path/to/workspace"; DashiBoard.launch(ws; data_dir = joinpath(ws, "data"), pipeline_dir = joinpath(ws, "pipeline"), filter_dir = joinpath(ws, "filter"), model_dir = joinpath(ws, "model"), training_dir = joinpath(ws, "training"))'
```

where `path/to/workspace` is the folder DashiBoard works in: its tables in `data/`, saved
pipelines in `pipeline/`, filters in `filter/`, model and training configurations in `model/`
and `training/`, as the keywords name them (each defaults to the workspace itself). A client's server runs instead from a deployment, installed once with
`bin/install.jl` from a `dashiboard.toml` that pins the release and its extensions; both are
described in `bin/README.md`.

## Launching the frontend

Open a terminal in the `dashiboard-ui` folder.

Install all required dependencies with the following command:

```
pnpm install
```

Then, launch the frontend with the following command:

```
pnpm run start
```

To interact with the UI, open your browser and navigate to the page [http://localhost:3000](http://localhost:3000).

The dev server proxies the Julia API, so the page and the API share an origin exactly as they will
when the bundle is served alongside the server.
