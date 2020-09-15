""" 
    PoptartExpr

Generate Poptart controls.

API is kept consistent with `Poptart.Desktop`
"""
module PoptartExpr

using Poptart.Desktop

export xpoptart_desktop, xpush_item, xexit

"""
`xcall` but support `Type` as function.

It is meant to be a private function.
"""
xcall_poptart(m::Module, name::Union{Type, Function}, xs...; kwargs...) = xcall_poptart(m, nameof(name), xs...; kwargs...)
xcall_poptart(m::Module, name::Symbol, xs...; kwargs...) = xcall_poptart(GlobalRef(m, name), xs...; kwargs...)

function xcall_poptart(ref::GlobalRef, xs...; kwargs...)
    params = Expr(:parameters)
    for (key, value) in kwargs
        if value isa Vector
            value = Expr(:vect, value...)
        end

        push!(params.args, Expr(:kw, key, value))
    end

    if isempty(kwargs)
        Expr(:call, ref, xs...)
    else
        return Expr(:call, ref, params, xs...)
    end
end

function xpoptart_desktop(control, xs...; kwargs...)
    xcall_poptart(Desktop, control, xs...; kwargs...)
end

const CONTROLS = (:Application, :Button, :InputText, :Window, :Checkbox, :Popup, :SameLine, :NewLine, :Label, :Slider, :Canvas, :Spacing, :Group, :Separator)

for control in CONTROLS
    funname = Symbol(:X, control)

    @eval export $funname

    @eval function ($funname)(; kwargs...)
        xpoptart_desktop($control; kwargs...)
    end

    @eval function ($funname)(control_var::Symbol; kwargs...)
        :($control_var = $(xpoptart_desktop($control; kwargs...)))
    end
end

const CLICKABLES = (:Button, :Checkbox)

for control in CLICKABLES
    funname = Symbol(:X, control)

    @eval function ($funname)(control_var::Symbol, click_event; kwargs...)
        click_function = :(function (event) $click_event end)
        quote
            $(($funname)(control_var; kwargs...))
            $(xpoptart_desktop(:didClick, click_function, control_var))
        end
    end
end

function xpush_item(control_var::Symbol, items...)
    ret = :(push!($control_var.items))
    append!(ret.args, items)
    ret
end

function xexit(app::Symbol; esc=true)
    quote
        Poptart.Desktop.exit_on_esc() = $esc
        Base.JLOptions().isinteractive==0 && wait($app.closenotify)
    end
end

end