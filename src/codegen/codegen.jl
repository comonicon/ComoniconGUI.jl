module CodeGen

import Base

using Poptart.Desktop
using ExprTools
using DataStructures
using Comonicon
using Comonicon.Types
using Comonicon.Types: CommandDoc
using Comonicon.CodeGen
using Comonicon.CodeGen: hasparameters

include("poptart.jl")

export codegen, PoptartCtx

end