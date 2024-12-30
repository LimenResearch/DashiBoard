# StreamlinerCore

## Installation instruction

Ensure that both `StreamlinerCore` and `ParametricMachines` are in your `.julia/dev` folder.

Start a console with `julia --project` in the top level of this repo. Then

```julia
(StreamlinerCore) pkg> resolve

(StreamlinerCore) pkg> instantiate
```

## Documentation build

Start a console with `julia --project=docs` in the top level of this repo. Then

```julia
(docs) pkg> resolve

(docs) pkg> instantiate

julia> include("docs/make.jl")
```

The documentation will be available in the `docs/build` folder.

It can be explored by, e.g, opening `docs/build/index.html` in your browser
or with VSCode live server.
