module Dragonstone
    module AST
        class BlockLiteral < Node
            getter typed_parameters : Array(TypedParameter)
            getter body : NodeArray

            def initialize(typed_parameters : Array(TypedParameter), body : NodeArray, location : Location? = nil)
                super(location: location)
                @typed_parameters = typed_parameters
                @body = body
            end

            def accept(visitor)
                visitor.visit_block_literal(self)
            end

            def to_source(io : IO)
                io << "{ "
                
                unless @typed_parameters.empty?
                    io << "| "
                    @typed_parameters.each_with_index do |param, index|
                        io << ", " if index > 0
                        param.to_source(io)
                    end
                    io << " | "
                end

                @body.each_with_index do |node, index|
                    io << "; " if index > 0
                    node.to_source(io)
                end
                
                io << " }"
            end
        end
    end
end
