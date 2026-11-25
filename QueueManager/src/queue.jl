"""
    AbstractJobQueue

Supertype for job queue backends (e.g. an in-process `Channel` based queue for
testing, or a Redis-backed queue for production).

Subtypes must implement [`queue_job!`](@ref), [`job_channel`](@ref) and
[`notification_channel`](@ref).
"""
abstract type AbstractJobQueue end

"""
    queue_job!(queue::AbstractJobQueue, job)

Enqueue `job` so that a worker running [`start_worker`](@ref) on `queue` can pick it up.
"""
function queue_job! end

"""
    job_channel(queue::AbstractJobQueue)

Return an object yielding queued jobs through Julia's iteration protocol
(`for job in job_channel(queue)`), analogous to a `Channel`.
"""
function job_channel end

"""
    notification_channel(queue::AbstractJobQueue)

Return an object that job results can be pushed onto with `put!`, analogous to
a `Channel`.
"""
function notification_channel end

"""
    start_worker(run_job, queue::AbstractJobQueue)

Repeatedly take jobs from `job_channel(queue)`, call `run_job(job, queue)` on each
(the queue is passed along so `run_job` can, e.g., queue follow-up jobs), and `put!`
the result onto `notification_channel(queue)`.

The loop ends once `job_channel(queue)` is exhausted (e.g. because the underlying
channel was closed).
"""
function start_worker(run_job, queue::AbstractJobQueue)
    jobs, notifications = job_channel(queue), notification_channel(queue)
    for job in jobs
        res = run_job(job, queue) # second argument to notify
        put!(notifications, res)
    end
    @info "Jobs completed"
    return
end
