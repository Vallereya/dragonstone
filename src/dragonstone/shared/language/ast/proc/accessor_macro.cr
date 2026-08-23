module Dragonstone
    module AST
        struct AccessorEntry
            getter name : String
            getter type_annotation : TypeExpression?

            def initialize(@name : String, @type_annotation : TypeExpression? = nil)
            end

            def to_source : String
                String.build { |io| to_source(io) }
            end

            def to_source(io : IO)
                io << name
                if type = type_annotation
                    io << ": "
                    type.to_source(io)
                end
            end
        end

        class AccessorMacro < Node
            getter kind : Symbol
            getter entries : Array(AccessorEntry)
            getter visibility : Symbol

            def initialize(kind : Symbol, entries : Array(AccessorEntry), visibility : Symbol = :public, location : Location? = nil)
                super(location: location)
                @kind = kind
                @entries = entries
                @visibility = visibility
            end

            def accept(visitor)
                visitor.visit_accessor_macro(self)
            end

            def to_source(io : IO)
                io << visibility << " " unless visibility == :public
                io << kind
                return if @entries.empty?
                io << " "
                @entries.each_with_index do |entry, index|
                    io << ", " if index > 0
                    entry.to_source(io)
                end
            end
        end
    end
end
