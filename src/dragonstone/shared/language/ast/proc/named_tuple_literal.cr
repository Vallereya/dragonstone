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
                String.build { |io| to_source(io) }
            end

            def to_source(io : IO)
                io << name << ": "
                if type = type_annotation
                    type.to_source(io)
                    io << " = "
                end
                value.to_source(io)
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

            def to_source(io : IO)
                io << "{"
                entries.each_with_index do |entry, index|
                    io << ", " if index > 0
                    entry.to_source(io)
                end
                io << "}"
            end
        end
    end
end
