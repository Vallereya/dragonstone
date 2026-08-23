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

            def to_source(io : IO)
                io << "fun"

                unless typed_parameters.empty?
                    io << "("
                    typed_parameters.each_with_index do |param, index|
                        io << ", " if index > 0
                        param.to_source(io)
                    end
                    io << ")"
                end

                if type = return_type
                    io << " : "
                    type.to_source(io)
                end

                io << "\n"

                body.each do |statement|
                    io << "  "
                    statement.to_source(io)
                    io << "\n"
                end

                io << "end"
            end
        end
    end
end
