module Dragonstone
    module AST
        struct NamedTupleEntry
            getter name : String
            getter value : Node
            getter type_annotation : TypeExpression?
            getter location : Location?

            def initialize(name : String, value : Node, type_annotation : TypeExpression? = nil, location : Location? = nil)
                @name = name
                @value = value
                @type_annotation = type_annotation
                @location = location
            end

            def to_source : String
                if type_annotation
                    "#{name}: #{type_annotation.not_nil!.to_source} = #{value.to_source}"
                else
                    "#{name}: #{value.to_source}"
                end
            end
        end

        class NamedTupleLiteral < Node
            getter entries : Array(NamedTupleEntry)

            def initialize(entries : Array(NamedTupleEntry), location : Location? = nil)
                super(location: location)
                @entries = entries
            end

            def accept(visitor)
                visitor.visit_named_tuple_literal(self)
            end

            def to_source : String
                inner = entries.map(&.to_source).join(", ")
                "{#{inner}}"
            end
        end
    end
end
