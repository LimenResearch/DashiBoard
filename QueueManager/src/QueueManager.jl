module QueueManager

export AbstractJobQueue, ChannelJobQueue

export queue_job!, job_channel, notification_channel, start_worker

include("queue.jl")
include("channel_queue.jl")

end
