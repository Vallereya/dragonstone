module Dragonstone
    module AST
        class QuitStatement < Node
            getter status : Node?

            def initialize(status : Node?, location : Location? = nil)
                super(location: location)
                @status = status
            end

            def accept(visitor)
                visitor.visit_quit_statement(self)
            end

            def to_source(io : IO)
                io << "quit"
                if node = status
                    io << " "
                    node.to_source(io)
                end
            end
        end
    end
end
