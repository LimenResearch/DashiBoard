"""
    ChannelJobQueue(size = Inf)

An [`AbstractJobQueue`](@ref) backed by in-process Julia `Channel`s.

Jobs queued with [`queue_job!`](@ref) and results produced by [`start_worker`](@ref)
never leave the current Julia process, which makes this backend well suited for
unit tests and other single-process usage. `size` controls the buffer size of the
underlying channels (see `Channel`); the default `Inf` makes `queue_job!` non-blocking.
"""
struct ChannelJobQueue <: AbstractJobQueue
    jobs::Channel{Any}
    notifications::Channel{Any}
end

ChannelJobQueue(size = Inf) = ChannelJobQueue(Channel(size), Channel(size))

queue_job!(queue::ChannelJobQueue, job) = put!(queue.jobs, job)

job_channel(queue::ChannelJobQueue) = queue.jobs

notification_channel(queue::ChannelJobQueue) = queue.notifications

"""
    Base.close(queue::ChannelJobQueue)

Close the underlying job and notification channels. This causes any
[`start_worker`](@ref) loop running on `queue` to finish once it has drained
pending jobs.
"""
function Base.close(queue::ChannelJobQueue)
    close(queue.jobs)
    close(queue.notifications)
    return
end
