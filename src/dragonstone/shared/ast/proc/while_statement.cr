module Dragonstone
    module AST
        class WhileStatement < Node
            getter condition : Node
            getter block : NodeArray

            def initialize(condition : Node, block : NodeArray, location : Location? = nil)
                super(location: location)
                @condition = condition
                @block = block
            end

            def accept(visitor)
                visitor.visit_while_statement(self)
            end
        end
    end
end
