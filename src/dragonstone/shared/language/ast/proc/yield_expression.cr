module Dragonstone
    module AST
        class YieldExpression < Node
            getter arguments : NodeArray

            def initialize(@arguments : NodeArray, location : Location? = nil)
                super(location: location)
            end

            def accept(visitor)
                visitor.visit_yield_expression(self)
            end

            def to_source(io : IO)
                io << "yield"
                return if arguments.empty?
                io << " "
                arguments.each_with_index do |argument, index|
                    io << ", " if index > 0
                    argument.to_source(io)
                end
            end
        end
    end
end
