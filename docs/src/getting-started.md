# Getting Started

DashiBoard is still in development, thus installing requires a few passages.

## Installation dependencies

- Julia programming language (minimum version 1.11, installable via [juliaup](https://github.com/JuliaLang/juliaup)).
- JavaScript package manager [pnpm](https://pnpm.io/).

## Launching the server

Open a terminal at the top-level of the repository.

Install all required dependencies with the following command:

```
julia --project -e 'using Pkg; Pkg.instantiate()'
```

Then, launch the server with the following command:

```
julia --project bin/launch.jl path/to/data
```

where `path/to/data` represents the data folder you wish to make accessible
to DashiBoard.

## Launching the frontend

Open a terminal in the `frontend` folder.

Install all required dependencies with the following command:

```
pnpm install
```

Then, launch the frontend with the following command:

```
pnpm run start
```

To interact with the UI, open your browser and navigate to the page [http://localhost:3000](http://localhost:3000).
