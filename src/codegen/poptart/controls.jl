""" 
    PoptartGen

Generate Poptart controls.

API is kept consistent with `Poptart.Desktop`
"""
module PoptartGen

using Poptart.Desktop

export xpoptart_desktop, xpush_item

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

const CONTROLS = (:Button, :InputText, :Window, :Checkbox, :Popup, :SameLine, :Label, :Slider, :Canvas, :Spacing, :Group, :Separator)

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

end