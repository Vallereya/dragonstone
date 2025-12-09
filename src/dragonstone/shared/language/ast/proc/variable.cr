module Dragonstone
    module AST
        class Variable < Node
            getter name : String
            getter type_annotation : TypeExpression?

            def initialize(name : String, type_annotation : TypeExpression? = nil, location : Location? = nil)
                super(location: location)
                @name = name
                @type_annotation = type_annotation
            end

            def accept(visitor)
                visitor.visit_variable(self)
            end

            # def to_source : String
            #     return name unless type_annotation
            #     "#{name}: #{type_annotation.not_nil!.to_source}"
            # end

            def to_source(io : IO)
                io << name
                if type = @type_annotation
                    io << ": "
                    type.to_source(io)
                end
            end
        end
    end
end
