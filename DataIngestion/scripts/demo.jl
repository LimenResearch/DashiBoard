using DataIngestion

my_exp = Experiment(name = "my_exp", prefix = "cache/", ext = ".txt")

DataIngestion.init!(my_exp)

partition = Partition(by=["_name"], sorters=["date, time"], tiles=[1,1,2,1,1,2])

register_partition(my_exp, partition)
