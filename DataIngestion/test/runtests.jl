using DataIngestion
using DuckDB, DataFrames
using Test

@testset "filtering" begin
    files = ["https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv"]
    my_exp = Experiment(; name = "my_exp", prefix = "data", files)
    DataIngestion.init!(my_exp)

    f1 = DataIngestion.IntervalFilter(
        "hour",
        DataIngestion.Interval(1, 3)
    )

    f2 = DataIngestion.ListFilter(
        "cbwd",
        ["NW", "SE"]
    )

    filters = DataIngestion.Filters(
        [f1],
        [f2]
    )

    query = DataIngestion.Query("my_exp", filters, ["hour", "cbwd"])

    # FIXME: rename types!
    clause = DataIngestion.Clause(query)

    df = DBInterface.execute(DataFrame, my_exp.repository, clause)
    @test unique(sort(df.cbwd)) == ["NW", "SE"]
    @test unique(sort(df.hour)) == [1, 2, 3]
    @test names(df) == ["hour", "cbwd"]
end
