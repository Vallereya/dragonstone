module Dragonstone
    module AST
        class FixDeclaration < Node
            getter name : String
            getter value : Node
            getter type_annotation : TypeExpression?
            getter visibility : Symbol

            def initialize(
                name : String,
                value : Node,
                type_annotation : TypeExpression? = nil,
                visibility : Symbol = :public,
                location : Location? = nil
            )
                super(location: location)
                @name = name
                @value = value
                @type_annotation = type_annotation
                @visibility = visibility
            end

            def accept(visitor)
                if visitor.responds_to?(:visit_fix_declaration)
                    visitor.visit_fix_declaration(self)
                else
                    nil
                end
            end

            def to_source(io : IO)
                io << "#{@visibility} " unless @visibility == :public
                io << "fix " << @name
                if type = @type_annotation
                    io << ": "
                    type.to_source(io)
                end
                io << " = "
                @value.to_source(io)
            end
        end
    end
end
