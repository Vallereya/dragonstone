module Dragonstone
    module AST
        class UnlessStatement < Node
            getter condition : Node
            getter body : NodeArray
            getter else_block : NodeArray?

            def initialize(condition : Node, body : NodeArray, else_block : NodeArray? = nil, location : Location? = nil)
                super(location: location)
                @condition = condition
                @body = body
                @else_block = else_block
            end

            def accept(visitor)
                visitor.visit_unless_statement(self)
            end

            def to_source(io : IO)
                io << "unless "
                condition.to_source(io)
                io << "\n"
                body.each do |stmt|
                    stmt.to_source(io)
                    io << "\n"
                end
                if e = else_block
                    io << "else\n"
                    e.each do |stmt|
                        stmt.to_source(io)
                        io << "\n"
                    end
                end
                io << "end"
            end
        end
    end
end
