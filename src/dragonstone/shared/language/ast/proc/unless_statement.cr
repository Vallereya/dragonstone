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
        end
    end
end
