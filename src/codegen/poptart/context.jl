"""
    PoptartCtx

Poptart code generation context.
"""
mutable struct PoptartCtx
    arg_inputs::OrderedDict{Arg, Symbol}
    option_inputs::Dict{Option, Symbol}
    flag_inputs::Dict{Flag, Symbol}
    leaf_windows::Dict{LeafCommand, Symbol}
    app::Symbol
    warning::Symbol
    help::Symbol
    version::Symbol
end

PoptartCtx() = PoptartCtx(OrderedDict{Arg, Symbol}(), 
                          Dict{Option, Symbol}(),
                          Dict{Flag, Symbol}(),
                          Dict{LeafCommand, Symbol}(),
                          gensym(:app), 
                          gensym(:warning), 
                          gensym(:help), 
                          gensym(:version))

"""
    Empty arguments-inputs mapping of context

It should be called for each window/casted function
"""
function empty_inputs!(ctx::PoptartCtx)
    ctx.arg_inputs = OrderedDict{Arg, Symbol}()
    ctx.option_inputs = Dict{Option, Symbol}()
    ctx.flag_inputs = Dict{Flag, Symbol}()
    ctx
end

"""
    codegen(cmd)

Generate Julia AST from given command object `cmd`. This will wrap
all the generated AST in a function `command_main`.
"""
function codegen(ctx::PoptartCtx, cmd::AbstractCommand)
    defs = Dict{Symbol,Any}()
    defs[:name] = :poptart_main
    defs[:args] = []

    defs[:body] = quote
        $(codegen_entry(ctx, cmd))
    end

    ret_app = gensym(:app)

    return quote
        import Poptart
        $(poptart_compat())
        
        $(combinedef(defs))
        $ret_app = poptart_main()

        $(xexit(ret_app;esc=false))
    end
end

function codegen_entry(ctx::PoptartCtx, cmd::EntryCommand)
    quote
        $(codegen_app(ctx, cmd_name(cmd)))
        $(codegen_body(ctx, cmd.root))
        return $(ctx.app)
    end
end

function codegen_body(ctx::PoptartCtx, cmd::LeafCommand)
    ret = Expr(:block)
    
    push!(ret.args, codegen_window(ctx, cmd), codegen_description(ctx, cmd))

    for args in (cmd.args, cmd.options, cmd.flags)
        expr = codegen_controls(ctx, args; cmd=cmd)
        push!(ret.args, expr)
    end

    button_run = gensym(:button_run)
    button_cancel = gensym(:button_cancel)

    params = gensym(:params)
    kwparams = gensym(:kwparams)

    run_event = quote
        $(ctx.warning).text = ""
        try
            $(codegen_params(ctx, params, kwparams, cmd))
            $(codegen_call(ctx, params, kwparams, cmd))
        catch e
            $(ctx.warning).text = string(e)
        end
    end
            
    cancel_event = xpoptart_desktop(:pause, ctx.app)

    button_expr = quote
        $(XButton(button_run, run_event, title = "run"))
        $(XButton(button_cancel, cancel_event, title = "cancel"))
        $(XLabel(ctx.warning, text = ""))
        $(xwindow_add_item(ctx, cmd, button_run, XSameLine(), button_cancel, ctx.warning))
    end
    push!(ret.args, button_expr)

    return ret
end

function codegen_body(ctx::PoptartCtx, cmd::NodeCommand)

    subcmd = gensym(:subcmd)
    ret = Expr(:block)

    for (i, subcmd) in enumerate(cmd.subcmds)
        push!(ret.args, codegen_body(ctx, subcmd))
        empty_inputs!(ctx)
    end

    push!(ret.args, codegen_entrywindow(ctx, cmd))

    ret
end

function codegen_entrywindow(ctx::PoptartCtx, cmd::NodeCommand)
    ret = Expr(:block)

    buttons = Symbol[]
    for (sub_cmd, window) in ctx.leaf_windows
        btn = gensym(:button)
        push!(ret.args, XWindowButton(btn, cmd_name(sub_cmd), window))
        push!(buttons, btn)
    end

    entry_window = gensym(:entrywindow)
    push!(ret.args, XWindow(entry_window, items=buttons, title=cmd_name(cmd)))
    push!(ret.args, :(push!($(ctx.app).windows, $entry_window)))
    ret
end


function codegen_app(ctx::PoptartCtx, appname::AbstractString="Comonicon")
    XApplication(ctx.app, title=appname, windows=[])
end

function codegen_window(ctx::PoptartCtx, cmd::LeafCommand)
    cmd_window = gensym(:window)
    ctx.leaf_windows[cmd] = cmd_window
    quote
        $(XWindow(cmd_window, title=cmd_name(cmd)))
        push!($(ctx.app).windows, $cmd_window)
    end
end

function codegen_description(ctx::PoptartCtx, cmd::LeafCommand)
    xwindow_add_item(ctx, cmd, XLabel(text = repr(cmd.doc)), XSeparator())
end

function codegen_params(ctx::PoptartCtx, params::Symbol, kwparams::Symbol, cmd::LeafCommand)
    hasparameters(cmd) || return
    args = gensym(:args)
    arg = gensym(:arg)

    ret = quote
        $params = []
        $(xget_args(ctx, args, ctx.arg_inputs))

        for $arg in $args
            if $arg === ""
                break
            end
            push!($params, $arg)
        end
        $kwparams = []
        $args = $(xget_kwargs(ctx, ctx.option_inputs))
        for $arg in $args
            if $arg.second === ""
                continue
            end
            push!($kwparams, $arg)
        end
        $args = $(xget_kwargs(ctx, ctx.flag_inputs))
        for $arg in $args
            push!($kwparams, $arg)
        end
    end
    ret
end

function xget_vararg(::PoptartCtx, args::Symbol, inputgroup::Symbol)
    input = gensym(:input)
    value = gensym(:value)
    quote
        for $input in $inputgroup.items
            $value = $input.buf
            push!($args, $value)
        end
    end
end

function xget_args(ctx::PoptartCtx, args::Symbol, arg_inputs::AbstractDict)
    ret = quote
        $args = []
    end
    params = ret.args[2].args[2]
    for (arg, input) in arg_inputs
        if arg.vararg
            push!(ret.args, xget_vararg(ctx, args, input))
        else
            value = inputvalue(ctx, arg, input)
            push!(params.args, value)
        end

    end
    ret
end

function xget_args(ctx::PoptartCtx, arg_inputs)
    ret = Expr(:vect)
    for (arg, input) in arg_inputs
        if arg.vararg
            continue
        end
        value = inputvalue(ctx, arg, input)
        push!(ret.args, value)

    end
    ret
end

function xget_kwargs(ctx::PoptartCtx, arg_inputs::AbstractDict)
    ret = :(Dict())
    for (arg, input) in arg_inputs
        value = inputvalue(ctx, arg, input)
        push!(ret.args, :($(QuoteNode(cmd_sym(arg))) => $value))
    end
    ret
end

function codegen_call(::PoptartCtx, params::Symbol, kwparams::Symbol, cmd::LeafCommand)
    ex_call = Expr(:call, cmd.entry)
    
    return :($(cmd.entry)($params...; $kwparams...))
end

function xwarn(ctx::PoptartCtx, message::AbstractString)
    :($(ctx.warning).Label = $message)
end

inputvalue(ctx::PoptartCtx, opt::Option, input::Symbol) = inputvalue(ctx, opt.arg, input)

function inputvalue(::PoptartCtx, arg::Arg, input::Symbol)
    if arg.type == Any
        value = :($input.buf)
    else
        value = :(parse($(arg.type), $input.buf))
    end
    value
end

function inputvalue(::PoptartCtx, flag::Flag, input::Symbol)
    :($input.value)
end

function Base.push!(ctx::PoptartCtx, arg_input::Pair{Arg, Symbol})
    push!(ctx.arg_inputs, arg_input)
end

function Base.push!(ctx::PoptartCtx, arg_input::Pair{Option, Symbol})
    push!(ctx.option_inputs, arg_input)
end

function Base.push!(ctx::PoptartCtx, arg_input::Pair{Flag, Symbol})
    push!(ctx.flag_inputs, arg_input)
end

function process_default(arg::Arg)
    process_default(arg.default)
end

function process_default(opt::Option)
    process_default(opt.arg.default)
end

function process_default(::Nothing)
    (buf="", tip="")
end

function process_default(value::Number)
    (buf=string(value), tip="")
end

function process_default(value::Expr)
    (buf="", tip="\nDefault value is $value")
end

function process_default(value::String)
    (buf="", tip="\nDefault value is $value")
end

function process_default(value)
    process_default(string(value))
end

function process_label(opt::Option)
    process_label(opt.arg, opt.doc)
end

function process_label(arg::Arg)
    process_label(arg, arg.doc)
end

function process_label(flag::Flag)
    label = flag.name * "::Bool"
    doc = flag.doc
    arg_docstring = string(doc)
    if arg_docstring != ""
        label *= "\n" * arg_docstring
    end
    label
end

function process_label(arg::Arg, doc::CommandDoc)
    label = arg.name
    if arg.type != Any
        label *= "::" * string(arg.type)
    end
    if arg.require
        label *= " *"
    end
    arg_docstring = string(doc)
    if arg_docstring != ""
        label *= "\n" * arg_docstring
    end
    label
end

"""
    Generate inputs for `args`
"""
function codegen_controls(ctx::PoptartCtx, args; cmd::LeafCommand)
    genexpr = Expr(:block)
    group = gensym(:group)
    push!(genexpr.args, quote
        $(XGroup(group, items = [XNewLine()]))
        $(xwindow_add_item(ctx, cmd, group))
    end
    )
    for arg in args
        expr, input = codegen_control(ctx, group, arg)
        push!(genexpr.args, expr)
    end
    return genexpr
end

function codegen_control(ctx::PoptartCtx, group::Symbol, arg)
    input_symbol = gensym(:input)
    expr = codegen_control(ctx, input_symbol, group, arg)
    push!(ctx, arg=>input_symbol)
    return expr, input_symbol
end

function is_vararg(arg::Arg)
    arg.vararg
end

function is_vararg(opt::Option)
    opt.arg.vararg
end

function codegen_control(ctx::PoptartCtx, input::Symbol, group::Symbol, arg::Union{Arg, Option})
    label = process_label(arg)

    buf, tip = process_default(arg)
    label *= tip
    if is_vararg(arg)
        codegen_control_vararg(ctx, input; name=arg.name, label=label, group=group)
    else
        codegen_control(ctx, input, buf; name=arg.name, label=label, group=group)
    end
end

function codegen_control_vararg(ctx::PoptartCtx, inputgroup::Symbol; name::AbstractString, label::AbstractString, group::Symbol)
    varaddbutton = gensym(:varaddbutton)
    inputcount = gensym(:inputcount)

    addbutton_event = :(
        try
            $inputcount[] += 1
            $(xpush_item(inputgroup, XInputText(label=:(repr($inputcount[])), buf="")))
        catch e 
            @error "error from addbutton" e
        end
    )

    quote
        $inputcount = Ref(0)
        $(XButton(varaddbutton, addbutton_event, title="+"))
        $(XGroup(inputgroup, items=[]))
        $(xpush_item(group, XLabel(text=label), XSameLine(), varaddbutton, inputgroup))
    end
end

function codegen_control(ctx::PoptartCtx, input::Symbol, group::Symbol, flag::Flag)
    label = process_label(flag)

    codegen_control(ctx, input, false; name=flag.name, label=label, group=group)
end

function codegen_control(::PoptartCtx, input::Symbol, buf::AbstractString; name::AbstractString, label::AbstractString, group::Symbol)
    quote
        $(XInputText(input, label=name, buf=buf))
        $(xpush_item(group, XLabel(text=label), input))
    end
end

function codegen_control(::PoptartCtx, input::Symbol, value::Bool; name::AbstractString, label::AbstractString, group::Symbol)
    quote
        $(XCheckbox(input, label=name, value=value))
        $(xpush_item(group, XLabel(text=label), input))
    end
end

"""
Get thw window symbol corresponding to the cmd
"""
function xcmd_window(ctx::PoptartCtx, cmd::LeafCommand)
    ctx.leaf_windows[cmd]
end

function xwindow_add_item(ctx::PoptartCtx, cmd::LeafCommand, items...)
    xpush_item(xcmd_window(ctx, cmd), items...)
end

"""
Generate a button that opens a window
"""
function XWindowButton(btn::Symbol, window_name::AbstractString, window::Symbol)
    openwindow = :(open_window($window))
    XButton(btn, openwindow; title=window_name)
end

"""
temporary

Will be removed once poptart is updated
"""
function poptart_compat()
    quote
        function open_window(window::Poptart.Desktop.Window)
            window_isopen(window) && return

            if !window.props[:show_window_closing_widget]
                window.props[:isopen] = C_NULL
            else
                window.props[:isopen] = Ref(true)
            end
            return
        end

        function window_isopen(window::Poptart.Desktop.Window)
            isopen_prop = window.props[:isopen]
            window_isopen(isopen_prop)
        end

        window_isopen(::Ptr{Nothing}) = true
        window_isopen(x::Ref{Bool}) = x[]
    end
end
