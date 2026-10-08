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
julia --project=DashiBoard bin/launch.jl path/to/workspace
```

where `path/to/workspace` is the folder DashiBoard works in: its tables in `data/`, saved
pipelines in `pipeline/`, filters in `filter/`, model and training configurations in `model/`
and `training/`. A plain folder of files can be sorted into that layout with
`bin/launch.jl path/to/folder --init`. The workspace, its `dashiboard.toml` and the launch flags
are described in `bin/README.md`.

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
