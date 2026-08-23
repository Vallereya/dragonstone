module Dragonstone
    module AST
        class Assignment < Node
            getter name : String
            getter value : Node
            getter operator : Symbol?
            getter type_annotation : TypeExpression?
            getter visibility : Symbol

            def initialize(
                name : String,
                value : Node,
                operator : Symbol? = nil,
                type_annotation : TypeExpression? = nil,
                visibility : Symbol = :public,
                location : Location? = nil
            )
                super(location: location)
                @name = name
                @value = value
                @operator = operator
                @type_annotation = type_annotation
                @visibility = visibility
            end

            def accept(visitor)
                visitor.visit_assignment(self)
            end

            def to_source(io : IO)
                io << visibility << " " unless operator || visibility == :public
                io << name
                if type = type_annotation
                    io << ": "
                    type.to_source(io)
                end

                if op = operator
                    io << " " << op << "= "
                else
                    io << " = "
                end
                value.to_source(io)
            end
        end
    end
end
