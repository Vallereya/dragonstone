module Dragonstone
    module AST
        class Literal < Node
            getter value : LiteralValue?

            def initialize(value : LiteralValue?, location : Location? = nil)
                super(location: location)
                @value = value
            end

            def accept(visitor)
                visitor.visit_literal(self)
            end

            def to_source(io : IO)
                io << value.inspect
            end
        end
    end
end
