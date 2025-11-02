module Dragonstone
    struct SymbolValue
        getter name : String

        def initialize(@name : String)
        end

        def to_s : String
            ":#{@name}"
        end

        def inspect(io : IO) : Nil
            io << to_s
        end

        def inspect : String
            to_s
        end

        def ==(other : SymbolValue) : Bool
            @name == other.name
        end

        def ==(other) : Bool
            other.is_a?(SymbolValue) && @name == other.name
        end

        def hash(hasher)
            @name.hash(hasher)
        end
    end
end
