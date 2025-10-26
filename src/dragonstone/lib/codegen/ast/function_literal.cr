module Dragonstone
    module AST
        class FunctionLiteral < Node
            getter parameters : Array(String)
            getter body : NodeArray
            getter rescue_clauses : RescueArray

            def initialize(parameters : Array(String), body : NodeArray, rescue_clauses : RescueArray = [] of RescueClause, location : Location? = nil)
                super(location: location)
                @parameters = parameters
                @body = body
                @rescue_clauses = rescue_clauses
            end

            def accept(visitor)
                visitor.visit_function_literal(self)
            end
        end
    end
end
