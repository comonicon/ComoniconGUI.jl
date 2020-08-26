export @main

"""
    PoptartCtx

Poptart code generation context.
"""
struct PoptartCtx

end

"""
    codegen(cmd)

Generate Julia AST from given command object `cmd`. This will wrap
all the generated AST in a function `command_main`.
"""
function Comonicon.codegen(cmd::AbstractCommand)
    defs = Dict{Symbol,Any}()
    defs[:name] = :command_main
    ctx = PoptartCtx()
    defs[:body] = quote
        # let Julia throw InterruptException on SIGINT
        # ccall(:jl_exit_on_sigint, Cvoid, (Cint,), 0)
        # $(codegen_scan_glob(ctx, cmd))
        $(codegen(ctx, cmd))
    end
    return quote
        using Poptart.Desktop
        window = Window()
        app = Application(windows = [window])
        $(combinedef(defs))
        Desktop.exit_on_esc() = true
        Base.JLOptions().isinteractive==0 && wait(app.closenotify)
    end
end

function codegen(ctx::PoptartCtx, cmd::EntryCommand)
    quote
        # $(codegen_help(ctx, cmd.root, xprint_help(cmd)))
        # $(codegen_version(ctx, cmd.root, xprint_version(cmd)))
        $(codegen_body(ctx, cmd.root))
    end
end

function codegen_body(ctx::PoptartCtx, cmd::LeafCommand)
    parameters = gensym(:parameters)
    n_args = gensym(:n_args)
    nrequires = nrequired_args(cmd.args)
    ret = Expr(:block)
    validate_ex = Expr(:block)

    pushmaybe!(ret, codegen_params(ctx, parameters, cmd))

    # if nrequires > 0
    #     err = xerror(
    #         :("command $($(cmd.name)) expect at least $($nrequires) arguments, got $($n_args)"),
    #     )
    #     push!(validate_ex.args, quote
    #         if $n_args < $nrequires
    #             $err
    #         end
    #     end)
    # end

    # # Error: too much arguments
    # if isempty(cmd.args) || !last(cmd.args).vararg
    #     nmost = length(cmd.args)
    #     err = xerror(:("command $($(cmd.name)) expect at most $($nmost) arguments, got $($n_args)"))
    #     push!(validate_ex.args, quote
    #         if $n_args > $nmost
    #             $err
    #         end
    #     end)
    # end

    # push!(ret.args, :($n_args = length(ARGS) - $(ctx.ptr - 1)))
    # push!(ret.args, validate_ex)
    # push!(ret.args, codegen_call(ctx, parameters, n_args, cmd))
    push!(ret.args, :(return 0))
    return ret
end

function codegen_params(ctx::PoptartCtx, params::Symbol, cmd::LeafCommand)
    hasparameters(cmd) || return

    regexes, actions = [], []
    controls = []
    arg = gensym(:arg)
    it = gensym(:index)

    for opt in cmd.options
        push!(regexes, regex_flag(opt))
        push!(regexes, regex_option(opt))

        push!(actions, read_forward(params, it, opt))
        push!(actions, read_match(params, it, opt))

        push!(controls, InputText(label=opt.name, buf=""))

        if opt.short
            push!(regexes, regex_short_flag(opt))
            push!(regexes, regex_short_option(opt))

            push!(actions, read_forward(params, it, opt))
            push!(actions, read_match(params, it, opt))
        end
    end

    for flag in cmd.flags
        push!(regexes, regex_flag(flag))
        push!(actions, read_flag(params, it, flag))

        if flag.short
            push!(regexes, regex_short_flag(flag))
            push!(actions, read_flag(params, it, flag))
        end
    end

    return quote
        # $params = []
        # $it = $(ctx.ptr)
        # while !isempty(ARGS) && $(ctx.ptr) <= $it <= length(ARGS)
        #     $arg = ARGS[$it]
        #     if startswith($arg, "-") # is a flag/option
        #         $(xmatch(regexes, actions, arg))
        #     else
        #         $it += 1
        #     end
        # end
     
        append!(window.items, $controls)
    end
end