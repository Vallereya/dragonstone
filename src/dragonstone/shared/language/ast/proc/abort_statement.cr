module Dragonstone
    module AST
        class AbortStatement < Node
            getter message : Node?

            def initialize(message : Node?, location : Location? = nil)
                super(location: location)
                @message = message
            end

            def accept(visitor)
                visitor.visit_abort_statement(self)
            end

            def to_source(io : IO)
                io << "abort"
                if node = message
                    io << " "
                    node.to_source(io)
                end
            end
        end
    end
end
