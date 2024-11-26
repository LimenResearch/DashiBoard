# Getting Started

DashiBoard is still in development, thus installing is requires a few passages.

## Installation dependencies

- Julia programming language (minimum version 1.11, installable via [juliaup](https://github.com/JuliaLang/juliaup)).
- JavaScript package manager [pnpm](https://pnpm.io/).

## Launching the server

Open a terminal at the top-level of the repository.

Install all required dependencies with the following command:

```
julia --project -e 'using Pkg; Pkg.add(Pkg.PackageSpec(name="DuckDB", rev="main")); Pkg.instantiate()'
```

Then, launch the server with the following command:

```
julia --project bin/launch.jl --host=127.0.0.1 --port=8080
```

## Launching the frontend

Open a terminal in the `dashiboard` folder, then run the following command:

```
pnpm run dev
```
