using Pkg: Pkg

Pkg.activate("DataIngestion")
Pkg.add(Pkg.PackageSpec(name="DuckDB", rev="main"))
Pkg.test()

Pkg.activate("Pipelines")
Pkg.add(Pkg.PackageSpec(name="DuckDB", rev="main"))
Pkg.test()
