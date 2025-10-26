module Dragonstone
    module AST
        class BinaryOp < Node
            getter left : Node
            getter operator : Symbol
            getter right : Node

            def initialize(left : Node, operator : Symbol, right : Node, location : Location? = nil)
                super(location: location)
                @left = left
                @operator = operator
                @right = right
            end

            def accept(visitor)
                visitor.visit_binary_op(self)
            end

            def to_source : String
                "#{left.to_source} #{operator} #{right.to_source}"
            end
        end
    end
end
