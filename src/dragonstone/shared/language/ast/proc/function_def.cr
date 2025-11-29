module Dragonstone
    module AST
        class FunctionDef < Node
            getter name : String
            getter typed_parameters : Array(TypedParameter)
            getter return_type : TypeExpression?
            getter body : NodeArray
            getter rescue_clauses : RescueArray
            getter visibility : Symbol
            getter receiver : Node?
            getter abstract : Bool

            def initialize(name : String, typed_parameters : Array(TypedParameter), body : NodeArray, rescue_clauses : RescueArray = [] of RescueClause, return_type : TypeExpression? = nil, visibility : Symbol = :public, receiver : Node? = nil, is_abstract : Bool = false, location : Location? = nil)
                super(location: location)
                @name = name
                @typed_parameters = typed_parameters
                @body = body
                @rescue_clauses = rescue_clauses
                @return_type = return_type
                @visibility = visibility
                @receiver = receiver
                @abstract = is_abstract
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
