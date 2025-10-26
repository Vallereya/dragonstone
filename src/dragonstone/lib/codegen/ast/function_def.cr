module Dragonstone
    module AST
        class FunctionDef < Node
            getter name : String
            getter parameters : Array(String)
            getter body : NodeArray
            getter rescue_clauses : RescueArray

            def initialize(name : String, parameters : Array(String), body : NodeArray, rescue_clauses : RescueArray = [] of RescueClause, location : Location? = nil)
                super(location: location)
                @name = name
                @parameters = parameters
                @body = body
                @rescue_clauses = rescue_clauses
            end

            def accept(visitor)
                visitor.visit_function_def(self)
            end
        end
    end
end
