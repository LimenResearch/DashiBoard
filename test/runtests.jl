using Pkg: Pkg

Pkg.add(Pkg.PackageSpec(name="DuckDB", rev="main"))
Pkg.test("DataIngestion")
Pkg.test("Pipelines")
