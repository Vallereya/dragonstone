module Dragonstone
    module AST
        class ReturnStatement < Node
            getter value : Node?

            def initialize(value : Node?, location : Location? = nil)
                super(location: location)
                @value = value
            end

            def accept(visitor)
                visitor.visit_return_statement(self)
            end

            def to_source(io : IO)
                io << "return"
                if node = value
                    io << " "
                    node.to_source(io)
                end
            end
        end
    end
end
