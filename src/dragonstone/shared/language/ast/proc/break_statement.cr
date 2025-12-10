module Dragonstone
    module AST
        class BreakStatement < Node
            getter condition : Node?
            getter condition_type : Symbol?

            def initialize(condition : Node? = nil, condition_type : Symbol? = nil, location : Location? = nil)
                super(location: location)
                @condition = condition
                @condition_type = condition_type
            end

            def accept(visitor)
                visitor.visit_break_statement(self)
            end

            def to_source(io : IO)
                io << "break"
                if cond = @condition
                    io << " if "
                    cond.to_source(io)
                end
            end
        end
    end
end
