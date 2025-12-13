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

            def to_source : String
                String.build do |io|
                    io << "while " << condition.to_source << "\n"
                    block.each do |stmt|
                        io << "  " << stmt.to_source << "\n"
                    end
                    io << "end"
                end
            end
        end
    end
end
