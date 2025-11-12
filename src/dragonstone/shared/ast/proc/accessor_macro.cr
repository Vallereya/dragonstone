module Dragonstone
    module AST
        struct AccessorEntry
            getter name : String
            getter type_annotation : TypeExpression?

            def initialize(@name : String, @type_annotation : TypeExpression? = nil)
            end

            def to_source : String
                return name unless type_annotation
                "#{name}: #{type_annotation.not_nil!.to_source}"
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

            def to_source : String
                entry_source = @entries.map(&.to_source).join(", ")
                prefix = visibility == :public ? "" : "#{visibility} "
                "#{prefix}#{kind} #{entry_source}".strip
            end
        end
    end
end
