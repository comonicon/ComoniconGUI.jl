using Poptart.Desktop
using ExprTools

macro main(ex)
    funcdef = splitdef(ex)
    args = funcdef[:args]
    if haskey(funcdef, :kwargs)
        kwargs = funcdef[:kwargs]
    else
        kwargs = nothing
    end

    genargs, args_inputs = gen_inputs(args...)
    genkwargs, kwargs_inputs = gen_inputs(kwargs...)

    quote
        $ex

        window = Window()
        app = Application(windows = [window])

        $genargs
        $genkwargs

        button_run = Button(title = "run")
        button_cancel = Button(title = "cancel")
        push!(window.items, button_run, button_cancel)

        didClick(button_run) do event
            # $mainfun_call
            $(funcall(funcdef[:name], args_inputs, kwargs_inputs))
        end

        Desktop.exit_on_esc() = true
        Base.JLOptions().isinteractive==0 && wait(app.closenotify)
    end |> esc
end

"""
Create codes that generate inputs
and a dict that maps each argument to input variable
"""
function gen_inputs(args...)
    genexpr = Expr(:block)
    arg_input_dict = Dict{Any, Symbol}()
    for arg in args
        expr, input = gen_input(arg)
        push!(genexpr.args, expr, :(push!(window.items, $input)))
        arg_input_dict[arg] = input
    end
    return genexpr, arg_input_dict
end

function gen_input(arg::Symbol)
    input_symbol = gensym(:input)
    label = string(arg)
    expr = :($input_symbol = InputText(label=$label, buf=""))
    return expr, input_symbol
end

function gen_input(arg::Expr)
    input_symbol = gensym(:input)

    if arg.head == :kw
        key, value = arg.args
        label = string(key)
        expr = :($input_symbol = InputText(label=$label, buf=string($value)))
    elseif arg.head == :(::)
        label = string(arg)
        expr = :($input_symbol = InputText(label=$label, buf=""))
    else
        @error "unexpected argument head" arg.head
    end
    return expr, input_symbol
end

function funcall(fun, args, kwargs)
    rtn = Expr(:call, fun)
    for (arg, input) in args
        if arg isa Symbol
            push!(rtn.args, :($input.buf))
        elseif arg.head == :(::)
            push!(rtn.args, :(parse($(arg.args[2]), $input.buf)))
        elseif arg.head == :kw
            key = arg.args[1]
            if key isa Symbol
                push!(rtn.args, :($input.buf))
            elseif key.head == :(::)
                push!(rtn.args, :(parse($(key.args[2]), $input.buf)))
            end
        end
    end
    for (arg, input) in kwargs
        if arg isa Symbol
            push!(rtn.args, Expr(:kw, arg, :($input.buf)))
        elseif arg.head == :(::)
            push!(rtn.args, Expr(:kw, arg.args[1], :(parse($(arg.args[2]), $input.buf))))
        elseif arg.head == :kw
            key = arg.args[1]
            if key isa Symbol
                push!(rtn.args, Expr(:kw, key, :($input.buf)))
            elseif key.head == :(::)
                push!(rtn.args, Expr(:kw, key.args[1], :(parse($(key.args[2]), $input.buf))))
            end
        end
    end
    rtn
end

@main function mainfun(a, b=1, c::Int=3; d, e=9, f::Int)
    println("running!")
    @info "Got args" a=a b=b c=c d=d e=e f=f
end