using QueueManager
using Test

@testset "ChannelJobQueue" begin
    queue = ChannelJobQueue()
    worker = @async start_worker(queue) do job, q
        job * 2
    end

    queue_job!(queue, 1)
    queue_job!(queue, 2)

    notifications = notification_channel(queue)
    @test take!(notifications) == 2
    @test take!(notifications) == 4

    close(queue)
    wait(worker)
    @test istaskdone(worker)
    @test !isopen(job_channel(queue))
end

@testset "run_job receives the queue as second argument" begin
    queue = ChannelJobQueue()
    seen = Ref{Any}(nothing)
    worker = @async start_worker(queue) do job, q
        seen[] = q
        job
    end

    queue_job!(queue, "hello")
    @test take!(notification_channel(queue)) == "hello"
    @test seen[] === queue

    close(queue)
    wait(worker)
end
