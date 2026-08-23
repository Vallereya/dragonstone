module Dragonstone
    module AST
        # Represents a single named argument in a method call, written as `name: value`.
        #
        # This is intentionally different from `NamedTupleLiteral`. Previously, an
        # unbraced `name: value` expression was parsed as a named tuple, which made a
        # call such as `f(1, b: 2)` pass a `NamedTuple` positionally instead of binding
        # `2` to the parameter named `b`. That behavior failed silently.
        #
        # The AST must distinguish these forms:
        #
        # - `f(a: 1)` passes `1` as the named argument `a`.
        # - `f({a: 1})` passes a `NamedTuple` as a regular positional argument.
        #
        # A named-argument node is not evaluated independently. Call-processing code
        # extracts its name and value to bind the argument, so only the value reaches
        # `accept`.
        class NamedArgument < Node
            getter name : String
            getter value : Node

            def initialize(@name : String, @value : Node, location : Location? = nil)
                super(location: location)
            end

            def accept(visitor)
                @value.accept(visitor)
            end

            def to_source(io : IO)
                io << @name << ": "
                @value.to_source(io)
            end

        end
    end
end
