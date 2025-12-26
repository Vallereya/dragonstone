module Dragonstone
    module AST
        class ConstantDeclaration < Node
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
                visitor.visit_constant_declaration(self)
            end

            def to_source : String
                type_str = ""
                if type = type_annotation
                    type_str = " : #{type.to_source}"
                end
                prefix = visibility == :public ? "" : "#{visibility} "
                "#{prefix}con #{name}#{type_str} = #{value.to_source}"
            end
        end
    end
end
