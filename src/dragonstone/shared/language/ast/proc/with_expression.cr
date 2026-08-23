module Dragonstone
    module AST
        class WithExpression < Node
            getter receiver : Node
            getter body : NodeArray

            def initialize(@receiver : Node, @body : NodeArray, location : Location? = nil)
                super(location: location)
            end

            def accept(visitor)
                visitor.visit_with_expression(self)
            end

            def to_source(io : IO)
                io << "with "
                receiver.to_source(io)
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
