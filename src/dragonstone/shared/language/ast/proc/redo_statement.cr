module Dragonstone
    module AST
        class RedoStatement < Node
            getter condition : Node?
            getter condition_type : Symbol?

            def initialize(condition : Node? = nil, condition_type : Symbol? = nil, location : Location? = nil)
                super(location: location)
                @condition = condition
                @condition_type = condition_type
            end

            def accept(visitor)
                visitor.visit_redo_statement(self)
            end

            def to_source(io : IO)
                io << "redo"
                if cond = @condition
                    io << " if "
                    cond.to_source(io)
                end
            end
        end
    end
end
