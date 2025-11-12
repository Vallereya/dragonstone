module Dragonstone
    module AST
        class IfStatement < Node
            getter condition : Node
            getter then_block : NodeArray
            getter elsif_blocks : Array(ElsifClause)
            getter else_block : NodeArray?

            def initialize(condition : Node, then_block : NodeArray, elsif_blocks : Array(ElsifClause) = [] of ElsifClause, else_block : NodeArray? = nil, location : Location? = nil)
                super(location: location)
                @condition = condition
                @then_block = then_block
                @elsif_blocks = elsif_blocks
                @else_block = else_block
            end

            def accept(visitor)
                visitor.visit_if_statement(self)
            end
        end
    end
end
