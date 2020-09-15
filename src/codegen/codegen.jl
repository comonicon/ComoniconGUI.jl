module CodeGen

import Base

# using Poptart.Desktop
using ExprTools
using DataStructures
using Comonicon
using Comonicon.Types
using Comonicon.Types: CommandDoc
using Comonicon.CodeGen
using Comonicon.CodeGen: hasparameters
import Comonicon.CodeGen: codegen 

include("poptart/expr.jl")
using .PoptartExpr
include("poptart/context.jl")

export codegen, PoptartCtx

end