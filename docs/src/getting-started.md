# Getting Started

DashiBoard is still in development, thus installing requires a few passages.

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
julia --project bin/launch.jl --host=127.0.0.1 --port=8080 path/to/data
```

where `path/to/data` represents the data folder you wish to make accessible
to DashiBoard.

## Launching the frontend

Open a terminal in the `dashiboard` folder, then run the following command:

```
pnpm run dev
```

This will inform you that your browser has now access to the data in the folder
`dashiboard/data` and will launch the UI frontend.

To interact with the UI, open your browser and navigate to the page `http://localhost:3000/`.
