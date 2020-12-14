module ObservablePmap

export opmap

using Distributed
using Observables

@enum Status st_waiting st_working st_done st_error

status_str(st::Status) = (" ", "→", "✓", "✗")[Int(st)+1]
indent(str, n) = join((" "^n * line for line in split(str,r"(\r)?\n")), "\n")
default_summarize( els, statuses, messages, ids, indentlevel=8 ) = sprint() do io
    for (i,(el,st,msg,id)) in enumerate(zip(els,statuses,messages,ids))
        print(io, status_str(st), " ", join(el,","))
        isnothing(id) || print(io, "\t(on worker $id)")
        println(io)
        println(io, indent(msg, indentlevel))
    end
end

"""
    summary, task = opmap(f, [::AbstractWorkerPool], c...;
                          schedule_now=true, summarize=default_summarize,
                          kwargs... )

Transform collection(s) `c` by applying `f` to each element using available
workers and tasks, by calling `Distributed.pmap`. The function `f` receives as
its first argument a callable `setmessage`, and may call `setmessaage(msg)` to
set a status message describing the worker's current status.
The returned `summary` is an `Observable` containing a summary string of all
workers' statuses including their status messages.
The summary may be customized by setting the `summarize` keyword argument.

The application of `f` across available workers is performed asynchronously in
the returned `task::Task`. Setting `schedule_now=false` prevents `opmap` from
scheduling the task.

The `ObservablePmap` module must be loaded on all workers before calling
`opmap`, e.g. by `@everywhere using ObservablePmap`.

Other positional and keyword arguments to `opmap` are the same as for `pmap`.

Example:
```jldoctest
@everywhere using ObservablePmap
using Observables # for `map` method below
summ, task = opmap(1:5; on_error=identity) do setmessage, x
    for i=1:5
        setmessage("\$i @ \$x")
        (10i+x==33) && error("Error at \$i")
        sleep(rand())
    end
end
html = map(x -> HTML("<pre>\$x</pre>"), summ)
```
"""
opmap( f, c...; kwargs... ) = opmap( f, default_worker_pool(), c...; kwargs... )
function opmap( f, p::AbstractWorkerPool, c...;
               schedule_now=true, summarize=default_summarize, kwargs... )
    els = collect(zip(c...))
    workers_ch = RemoteChannel(()->Channel(Inf))

    pmap_task = Task(()->pmap(p, eachindex(els); kwargs...) do i
        setmessage(msg) = put!( workers_ch, (myid(), i, msg) )
        setmessage(st_working)
        try
            f( setmessage, els[i]... )
        catch e
            setmessage(sprint(showerror,e,catch_backtrace()))
            setmessage(st_error)
            rethrow()
        end
        setmessage(st_done)
    end)

    messages = Any["" for el in els]
    worker_ids = Union{Int,Nothing}[nothing for el in els]
    statuses = [st_waiting for el in els]
    active = Set(eachindex(els))
    summ = Observable(summarize(els,statuses,messages,worker_ids))

    summary_task = Task(()->begin
        while !isempty(active)
            id, i, msg = take!(workers_ch)
            worker_ids[i] = id
            if msg isa Status
                statuses[i] = msg
                if msg ∈ (st_done, st_error)
                    pop!(active, i)
                end
            else
                messages[i] = msg
            end
            # `invokelatest` as workaround to world-age issues (`Observables` issue #50)
            Base.invokelatest(setindex!, summ, summarize(els,statuses,messages,worker_ids))
            #summ[] = summarize(els,statuses,messages,worker_ids)
        end
    end)

    schedule_now && schedule(pmap_task)
    schedule(summary_task)

    summ, pmap_task, summary_task
end

end
