module Dragonstone
    module AST
        class FunctionLiteral < Node
            getter typed_parameters : Array(TypedParameter)
            getter return_type : TypeExpression?
            getter body : NodeArray
            getter rescue_clauses : RescueArray

            def initialize(typed_parameters : Array(TypedParameter), body : NodeArray, rescue_clauses : RescueArray = [] of RescueClause, return_type : TypeExpression? = nil, location : Location? = nil)
                super(location: location)
                @typed_parameters = typed_parameters
                @body = body
                @rescue_clauses = rescue_clauses
                @return_type = return_type
            end

            def parameters : Array(String)
                @typed_parameters.map(&.name)
            end

            def accept(visitor)
                visitor.visit_function_literal(self)
            end
        end
    end
end
