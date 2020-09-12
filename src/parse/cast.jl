# This file is adapted from 
const CACHE_FLAG = Ref{Bool}(true)

"""
    enable_cache()

Enable command compile cache. See also [`disable_cache`](@ref).
"""
function enable_cache()
    CACHE_FLAG[] = true
    return
end

"""
    disable_cache()

Disable command compile cache. See also [`enable_cache`](@ref).
"""
function disable_cache()
    CACHE_FLAG[] = false
    return
end

"""
    @cast <function expr>
    @cast <module expr>
    @cast <function name>
    @cast <module name>

Cast a Julia object to a command object. `@cast` will
always execute the given expression, and only create and
register an command object via [`command`](@ref) after
analysing the given expression.

# Example

The most basic way is to use `@cast` on a function as your command
entry.

```julia
@cast function your_command(arg1, arg2::Int)
    # your processing code
end
```

This will create a [`LeafCommand`](@ref) object and register it
to the current module's `CASTED_COMMANDS` constant. You can access
this object via `MODULE_NAME.CASTED_COMMANDS["your_command"]`.

Note this will not create a functional CLI, to create a function
CLI you need to create an entry point, which can be declared by
[`@main`](@ref).
"""
macro cast(ex)
    if CACHE_FLAG[] && iscached()
        return esc(ex)
    else
        return esc(cast_m(__module__, QuoteNode(__source__), ex))
    end
end

function cast_m(m::Module, line::QuoteNode, ex)
    ret = Expr(:block)
    pushmaybe!(ret, create_casted_commands(m))

    if ex isa Symbol
        push!(ret.args, parse_module(m, line, ex))
        return ret
    end

    def = splitdef(ex; throw = false)
    if def === nothing
        push!(ret.args, parse_module(m, line, ex))
        return ret
    end

    push!(ret.args, parse_function(m, line, ex, def))
    return ret
end

# Entry
"""
    @main <function expr>
    @main [options...]

Create an `EntryCommand` and use it as the entry of the entire CLI.
If you only have one function to cast to a CLI, you can use `@main`
instead of `@cast` so it will create both the command object and
the entry.

If you have declared commands via `@cast`, you can create the entry
via `@main [options...]`, available options are:

- `name`: default is the current module name in lowercase.
- `version`: default is the current project version or `v"0.0.0"`. If
    it's `v"0.0.0"`, the version will not be printed.
- `doc`: a description of the entry command.
"""
macro main(xs...)
    return esc(main_m(__module__, QuoteNode(__source__), xs...))
end

function main_m(m::Module, line::QuoteNode, ex::Expr)
    if CACHE_FLAG[] && iscached()
        return quote
            Core.@__doc__ $ex
            include($(cachefile()[1]))
        end
    end

    ret = Expr(:block)
    def = splitdef(ex; throw = false)
    var_cmd, var_entry = gensym(:cmd), gensym(:entry)
    push!(ret.args, ex)

    if def === nothing
        ex.head === :(=) && return create_entry(m, line, ex)
        ex.head === :module ||
            throw(Meta.ParseError("invalid expression, can only cast functions or modules"))
        cmd = xcall(command, ex.args[2]; line = line)
        push!(ret.args, :($var_cmd = $cmd))
    else
        push!(ret.args, :(Core.@__doc__ $(def[:name])))
        cmd = xcall(command, def[:name], parse_args(def), parse_kwargs(def); line = line)
        push!(ret.args, :($var_cmd = $cmd))
    end

    push!(ret.args, :($var_entry = $(xcall(Types, :EntryCommand, var_cmd; version = get_version(m)))))
    push!(ret.args, precompile_or_exec(m, var_entry))
    return ret
end

function main_m(m::Module, line::QuoteNode, ex::Symbol)
    CACHE_FLAG[] && iscached() && return :(include($(cachefile()[1])))
    var_cmd, var_entry = gensym(:cmd), gensym(:entry)
    quote
        $var_cmd = $(xcall(command, ex; line = line))
        $var_entry = $(xcall(Types, :EntryCommand, var_cmd; line = line))
        $(precompile_or_exec(m, var_entry))
    end
end

function main_m(m::Module, line::QuoteNode, kwargs...)
    CACHE_FLAG[] && iscached() && return :(include($(cachefile()[1])))
    return create_entry(m, line, kwargs...)
end

function create_entry(m::Module, line::QuoteNode, kwargs...)
    configs = Dict{Symbol,Any}(:name => default_name(m), :version => get_version(m), :doc => "")
    for kw in kwargs
        for key in [:name, :version, :doc]
            if kw.args[1] === key
                configs[key] = kw.args[2]
            end
        end
    end

    ret = Expr(:block)

    var_cmd, var_entry = gensym(:cmd), gensym(:entry)
    cmd = xcall(
        Types,
        :NodeCommand,
        configs[:name],
        line,
        configs[:doc],
        :(collect(values($m.CASTED_COMMANDS))),
    )
    entry = xcall(Types, :EntryCommand, var_cmd, configs[:version], line)

    push!(ret.args, :($var_cmd = $cmd))
    push!(ret.args, :($var_entry = $entry))
    push!(ret.args, precompile_or_exec(m, var_entry))
    return ret
end

function precompile_or_exec(m::Module, entry)
    if m == Main && CACHE_FLAG[]
        return quote
            $create_cache($entry)
            include($(cachefile()[1]))
        end
    elseif m == Main
        return quote
            $(xcall(m, :eval, xcall(CodeGen, :codegen, entry)))
            poptart_main()
        end
    else
        quote
            $create_cache($entry)

            $(create_casted_commands(m))
            $(xcall(set_cmd!, casted_commands(m), entry, "main"))
            $(xcall(m, :eval, xcall(CodeGen, :codegen, entry)))

            precompile(Tuple{typeof($m.poptart_main),Array{String,1}})
        end
    end
end
