# Note:
# This module is meant to be removed from ComoniconGUI when Comonicon itself is ready.

module Parse

using ExprTools
using Comonicon.Types
using Comonicon.CodeGen: prettify, pushmaybe!
using Comonicon.Parse
using Comonicon.Parse: xcall, checksum
using Comonicon.Parse: parse_args, parse_kwargs, parse_function
using Comonicon.Parse: create_casted_commands, casted_commands, set_cmd!

using ComoniconGUI
using ComoniconGUI.CodeGen

include("utils.jl")
include("cast.jl")

export @cast, @main,
        iscached,
        cachefile,
        create_cache,
        enable_cache,
        disable_cache

end