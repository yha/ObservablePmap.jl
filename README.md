# ObservablePmap

*distributed `map` returning an observable for following worker progress*

Example: running some fake work and viewing worker state in IJulia or Juno plot pane using HTML:
```
using Distributed
addprocs(2)

@everywhere using ObservablePmap
using WebIO, CSSUtil, Observables

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

html = map(x -> HTML("<pre>$x</pre>"), summ)
schedule(pmap_task)
vbox(html)  # not necessary on IJulia
```
