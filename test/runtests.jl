using Test
using ObservablePmap
using Distributed
using Observables

addprocs(2)
#addprocs(2; exeflags="--project")

@everywhere using ObservablePmap

_summ( els, statuses, messages, ids ) = copy(messages)
@testset "schedule_now=$schedule_now, worker_arg=$worker_arg" for
                    schedule_now in (false,true), worker_arg in (false,true)
    v = ["a", "b", "c"]
    args = worker_arg ? (default_worker_pool(), v) : (v,)
    summ, task = opmap(args...; schedule_now=schedule_now,
                    summarize=_summ, on_error=identity) do setmessage, x
        for i in 1:3
            #println(i)
            setmessage("$x $i")
            x == 2 && error()
            #sleep(rand())
        end
    end

    all_summaries = []
    on(summ) do x
        push!(all_summaries, x)
    end
    if schedule_now
        i = 0
        while !istaskstarted(task) && i < 10
            #println("Waiting for task...")
            sleep(0.1)
            i += 1
        end
        @test istaskstarted(task)
    else
        @test !istaskstarted(task)
        schedule(task)
    end
    wait(task)

    a,b,c = eachrow(reduce(hcat, all_summaries))
    ua,ub,uc = unique.((a,b,c))

    @test ua == ["", "a 1", "a 2", "a 3"]
    @test ub == ["", "b 1", "b 2", "b 3"]
    @test uc == ["", "c 1", "c 2", "c 3"]
    for (x,ux) in ((a,ua),(b,ub),(c,uc))
        @test all(in((0,1)), diff(indexin(x,ux)))
    end
end
