# ObservablePmap

*distributed `map` returning an observable for following worker progress*

## Directly setting worker status message – `opmap`
The `opmap` function is a wrapper around `pmap` which allows workers to report their status. The function passed to `opmap` takes as its first argument a callback `setmessage` that can be used to set a status message for the current worker. Unlike `pmap`, the mapping is performed asynchronously. `opmap` returns an `Observable` summary string of worker statuses, and the `Task` performing the mapping.

### Example 
Running some fake work and viewing worker state in IJulia or Juno plot pane using HTML:
```
using Distributed
addprocs(2)

@everywhere using ObservablePmap
using CSSUtil: vbox

obs, task = opmap(1:5; schedule_now=false, on_error=identity) do setmessage, x
    setmessage("Initializing...")
    sleep(1)
    n = rand(2:10)
    for i=1:n
        setmessage("Fooing $x-bars ($i/$n) ")
        x==3 && error("Error at $i")
        sleep(rand())
    end
    setmessage("All $x-bars successfully fooed.")
end

html = map(x -> HTML("<pre>$x</pre>"), obs)
schedule(task)
vbox(html)  # not necessary on IJulia
```
Here's what the output looks like in Juno's plot pane:

<img src="https://raw.githubusercontent.com/yha/ObservablePmap.jl/master/opmap-html-output.gif" width="600" />

## Observing log messages – `ologpmap`
When using `ologpmap`, log messages produced by workers are used as their status message. Accordingly, the function argument to `ologpmap` does *not* take an additional `setmessage` argument. By default, log messages in workers are processed by a `Base.CoreLogging.SimpleLogger`, and its output is used as the status message. The `logger_f` keyword argument to `ologpmap` can be used to specify a different logger: specifically, `logger_f(io)` should produce a logger writing log messages to `io`.
### Example
This example uses `ProgressLogging.jl` and `TerminalLogger.jl` to show progress bars.
```
using Distributed
addprocs(2)
@everywhere using ObservablePmap
@everywhere using ProgressLogging
@everywhere using TerminalLoggers
using CSSUtil: vbox

summ, task = ologpmap( 'a':'e', 2:2:10; logger_f=TerminalLogger ) do c, x
    @withprogress name="Processing '$c'" for i=1:x
        sleep(rand())
        @logprogress i/x
    end
    @info "finished '$c'."
    x
end

html = map(x -> HTML("<pre>$x</pre>"), summ)
vbox(html)
```

<img src="https://raw.githubusercontent.com/yha/ObservablePmap.jl/master/ologpmap-html-output.gif" width="800" />

