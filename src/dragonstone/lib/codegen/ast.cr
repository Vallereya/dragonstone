# ---------------------------------
# -------------- AST --------------
# ---------------------------------
require "../resolver/*"

module Dragonstone
    module AST
        alias NodeArray = Array(Node)
        alias RescueArray = Array(RescueClause)
        alias StringParts = Array(Tuple(Symbol, String))
        alias LiteralValue = Nil | Bool | Int64 | Float64 | String | Char

        abstract class Node
            getter location : Location?

            def initialize(@location : Location? = nil)
            end

            abstract def accept(visitor)

            def to_source : String
                raise NotImplementedError.new("#{self.class} must implement #to_source")
            end

            # I avoided dynamic String -> Symbol conversion to keep compatibility
            # across Crystal versions for some reason I have 3 versions. Names are 
            # kept as String for now.

            # I also broke this up so when I add more it doesn't get super long.
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

require "./ast/*"
