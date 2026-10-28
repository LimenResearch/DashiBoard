abstract type AbstractJobQueue end

function queue_job! end

function job_channel end

function notification_channel end

function start_worker(run_job, queue::AbstractJobQueue)
    jobs, notifications = job_channel(queue), notification_channel(queue)
    for job in jobs
        res = run_job(job, queue) # second argument to notify
        put!(notifications, res)
    end
    @info "Jobs completed"
    return
end
