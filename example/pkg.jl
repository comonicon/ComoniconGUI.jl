using ComoniconGUI

# pkg activate <string> --shared=false

module PkgCmd

using ComoniconGUI

"""
activate the environment at `path`.


# Arguments

- `path`: the path of the environment

# Flags

- `--shared`: whether activate the shared environment
"""
@cast function activate(path; shared::Bool = false)
    println("activating $path (shared=$shared)")
end

"""
deactivate the environment at `path`.


# Arguments

- `path`: the path of the environment

# Flags

- `--shared`: whether activate the shared environment
"""
@cast function deactivate(path; shared::Bool = false)
    println("deactivating $path (shared=$shared)")
end

@main

end

PkgCmd.poptart_main()
