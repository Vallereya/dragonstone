# ---------------------------------
# -------------- AST --------------
# ---------------------------------
require "../diagnostics/errors"
require "../../runtime/symbol"

module Dragonstone
    module AST
        alias NodeArray = Array(Node)
        alias RescueArray = Array(RescueClause)
        alias StringParts = Array(Tuple(Symbol, String))
        alias LiteralValue = Nil | Bool | Int64 | Float64 | String | Char | SymbolValue

        abstract class Node
            getter location : Location?

            def initialize(@location : Location? = nil)
            end

            abstract def accept(visitor)

            def to_source : String
                String.build do |io|
                    to_source(io)
                end
            end

            def to_source(io : IO)
                raise NotImplementedError.new("#{self.class} must implement #to_source(io : IO)")
            end
        end

        class Program < Node
            getter use_decls : Array(UseDecl)
            getter statements : NodeArray

            def initialize(statements : NodeArray, use_decls : Array(UseDecl) = [] of UseDecl, location : Location? = nil)
                super(location: location)
                @statements = statements
                @use_decls = use_decls
            end

            def accept(visitor)
                visitor.visit_program(self)
            end
        end
    end
end

require "./proc/*"
