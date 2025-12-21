module Dragonstone
    module AST
        class MapLiteral < Node
            getter entries : Array(Tuple(Node, Node))
            getter key_type : TypeExpression?
            getter value_type : TypeExpression?

            def initialize(entries : Array(Tuple(Node, Node)), @key_type : TypeExpression? = nil, @value_type : TypeExpression? = nil, location : Location? = nil)
                super(location: location)
                @entries = entries
            end

            def accept(visitor)
                visitor.visit_map_literal(self)
            end

            # def to_source : String
            #     inner = entries.map { |(key, value)| "#{key.to_source} -> #{value.to_source}" }.join(", ")
            #     "{#{inner}}"
            # end

            def to_source(io : IO)
                io << "{"
                @entries.each_with_index do |(key, value), index|
                    io << ", " if index > 0
                    key.to_source(io)
                    io << ": "
                    value.to_source(io)
                end
                io << "}"

                if @key_type && @value_type
                    io << " as "
                    @key_type.not_nil!.to_source(io)
                    io << " -> "
                    @value_type.not_nil!.to_source(io)
                end
            end
        end
    end
end
