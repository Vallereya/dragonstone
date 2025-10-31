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

            def to_source : String
                params = if typed_parameters.empty?
                    ""
                else
                    "| #{typed_parameters.map(&.to_source).join(", ")} | "
                end
                body_source = body.map(&.to_source).join("; ")
                "{ #{params}#{body_source} }"
            end
        end
    end
end

