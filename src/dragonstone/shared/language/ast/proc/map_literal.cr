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

            def to_source : String
                inner = entries.map { |(key, value)| "#{key.to_source} -> #{value.to_source}" }.join(", ")
                "{#{inner}}"
            end
        end
    end
end

