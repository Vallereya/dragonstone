module Dragonstone
    module AST
        class MapLiteral < Node
            getter entries : Array(Tuple(Node, Node))

            def initialize(entries : Array(Tuple(Node, Node)), location : Location? = nil)
                super(location: location)
                @entries = entries
            end

            def accept(visitor)
                visitor.visit_map_literal(self)
            end

            def to_source(io : IO)
                io << "{"
                @entries.each_with_index do |(key, value), index|
                    io << ", " if index > 0
                    key.to_source(io)
                    io << ": "
                    value.to_source(io)
                end
                io << "}"
            end
        end
    end
end
