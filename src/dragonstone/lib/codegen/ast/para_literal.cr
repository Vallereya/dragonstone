module Dragonstone
    module AST
        class ParaLiteral < Node
            getter typed_parameters : Array(TypedParameter)
            getter body : NodeArray
            getter rescue_clauses : RescueArray
            getter return_type : TypeExpression?

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
                visitor.visit_para_literal(self)
            end

            def to_source : String
                params = typed_parameters.map(&.to_source).join(", ")
                body_source = body.map(&.to_source).join("; ")
                arrow = params.empty? ? "-> { #{body_source} }" : "->(#{params}) { #{body_source} }"
                if return_type
                    "#{arrow} : #{return_type.not_nil!.to_source}"
                else
                    arrow
                end
            end
        end
    end
end
