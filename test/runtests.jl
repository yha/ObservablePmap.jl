using Test
using ObservablePmap
using Distributed
using Observables
using Logging

addprocs(2)
#addprocs(2; exeflags="--project")

@everywhere using ObservablePmap

_summ( els, statuses, messages, ids ) = copy(messages)
@testset "schedule_now=$schedule_now, worker_arg=$worker_arg" for
                    schedule_now in (false,true), worker_arg in (false,true)
    function test_pmap_output(summ, task, v, r)
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
        ra,rb,rc = r

        @test all(!isnothing, match.(ra,ua))
        @test all(!isnothing, match.(rb,ub))
        @test all(!isnothing, match.(rc,uc))
        for (x,ux) in ((a,ua),(b,ub),(c,uc))
            @test all(in((0,1)), diff(indexin(x,ux)))
        end
    end

    v = ["a", "b", "c"]
    args = worker_arg ? (default_worker_pool(), v) : (v,)
    summ, task = opmap(args...; schedule_now=schedule_now,
                    summarize=_summ, on_error=identity) do setmessage, x
        for i in 1:3
            setmessage("$x $i")
        end
    end

    test_pmap_output(summ, task, v,
            [[r"^$", r"^a 1$", r"^a 2$", r"^a 3$"],
             [r"^$", r"^b 1$", r"^b 2$", r"^b 3$"],
             [r"^$", r"^c 1$", r"^c 2$", r"^c 3$"]],
    )

    summ, task = ologpmap(args...; schedule_now=schedule_now,
                    summarize=_summ, on_error=identity) do x
        for i in 1:3
            @info "$x $i"
        end
    end
    test_pmap_output(summ, task, v,
            [[r"^$", r"┌ Info: a 1\n└ @ Main.*$",
                     r"┌ Info: a 2\n└ @ Main.*$",
                     r"┌ Info: a 3\n└ @ Main.*$"],
             [r"^$", r"┌ Info: b 1\n└ @ Main.*$",
                     r"┌ Info: b 2\n└ @ Main.*$",
                     r"┌ Info: b 3\n└ @ Main.*$"],

             [r"^$", r"┌ Info: c 1\n└ @ Main.*$",
                     r"┌ Info: c 2\n└ @ Main.*$",
                     r"┌ Info: c 3\n└ @ Main.*$"]]
    )

end
