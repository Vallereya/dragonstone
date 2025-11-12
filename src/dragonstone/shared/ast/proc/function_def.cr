module Dragonstone
    module AST
        class FunctionDef < Node
            getter name : String
            getter typed_parameters : Array(TypedParameter)
            getter return_type : TypeExpression?
            getter body : NodeArray
            getter rescue_clauses : RescueArray
            getter visibility : Symbol

            def initialize(name : String, typed_parameters : Array(TypedParameter), body : NodeArray, rescue_clauses : RescueArray = [] of RescueClause, return_type : TypeExpression? = nil, visibility : Symbol = :public, location : Location? = nil)
                super(location: location)
                @name = name
                @typed_parameters = typed_parameters
                @body = body
                @rescue_clauses = rescue_clauses
                @return_type = return_type
                @visibility = visibility
            end

            def parameters : Array(String)
                @typed_parameters.map(&.name)
            end

            def accept(visitor)
                visitor.visit_function_def(self)
            end
        end
    end
end
