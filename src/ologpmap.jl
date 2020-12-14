using Logging

struct ForwardLogger{L,IO,F} <: AbstractLogger
    logger::L
    io::IO
    forwarder::F
    function ForwardLogger(forwarder::F, logger_f, io::IO=IOBuffer()) where {F,IO}
        logger = logger_f(io)
        new{typeof(logger),IO,F}(logger, io, forwarder)
    end
end

function Logging.handle_message(fwdl::ForwardLogger, args...; kwargs...)
    Logging.handle_message(fwdl.logger, args...; kwargs...)
    fwdl.forwarder(take!(fwdl.io))
end
Logging.min_enabled_level(fwdl::ForwardLogger) = Logging.min_enabled_level(fwdl.logger)
Logging.shouldlog(fwdl::ForwardLogger, args...) = Logging.shouldlog(fwdl.logger, args...)

"""
    summary, task = ologpmap(f, [::AbstractWorkerPool], c...;
                          logger_f=SimpleLogger, schedule_now=true,
                          summarize=default_summarize,
                          kwargs... )

Transform collection(s) `c` by applying `f` to each element using available
workers and tasks, by calling `Distributed.pmap`.
The returned `summary` is an `Observable` containing a summary string of each
worker's last log message (emitted by each worker using the `Logging` interface).
The keyword argument `logger_f` is invoked with an `IOBuffer` internal to each
worker to create a logger writing messages to this buffer. Log message read from
this buffer are used as the worker's current status message included in the
observable `summary`.

The summary may be customized by setting the `summarize` keyword argument.

The `ObservablePmap` module must be loaded on all workers before calling
`ologpmap`, e.g. by `@everywhere using ObservablePmap`.

Other positional and keyword arguments to `ologpmap` are the same as for `opmap`.

Example:
```jldoctest
@everywhere using ObservablePmap
@everywhere using ProgressLogging
@everywhere using TerminalLoggers
summ, task = ologpmap( 'a':'e', 2:2:10;
                       on_error=identity, logger_f=TerminalLogger ) do c, x
    @withprogress name="processing '\$c'" for i=1:x
        sleep(rand())
        @logprogress i/x
    end
    @info "finished '\$c'"
    x
end
html = map(x -> HTML("<pre>\$x</pre>"), summ)
```
"""
ologpmap( f, c...; kwargs... ) = ologpmap( f, default_worker_pool(), c...; kwargs... )
function ologpmap( f, p::AbstractWorkerPool, c...; logger_f=SimpleLogger, kwargs... )
    opmap( p, c...; kwargs... ) do setmessage, x...
        fwdlogger = ForwardLogger( setmessage∘String, logger_f )
        with_logger(fwdlogger) do
            f(x...)
        end
    end
end
