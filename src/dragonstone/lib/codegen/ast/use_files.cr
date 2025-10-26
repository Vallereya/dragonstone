module Dragonstone
    module AST

        # This is so we can require other files, in this case:
        # use { Foo, bar as baz } from "./path.ds"
        struct NamedImport
            getter name : String
            getter alias_name : String?

            def initialize(@name : String, @alias_name : String? = nil)
            end

            def to_source : String
                alias_name ? "#{name} as #{alias_name}" : name
            end
        end

        enum UseItemKind
            Paths   # The our paths: "./foo.ds", "./*", "./**", "../lib/*.ds, etc."
            From    # Selectively require an import from a single file.
        end

        # Not a Node on purpose (keeps visitors simple). 
        # Part of UseDecl.
        struct UseItem
            getter kind : UseItemKind
            getter specs : Array(String)            # for Paths
            getter from  : String?                  # for From clause: the source file
            getter imports : Array(NamedImport)     # for From clause: selected names

            def initialize(
                @kind : UseItemKind,
                @specs : Array(String) = [] of String,
                @from : String? = nil,
                @imports : Array(NamedImport) = [] of NamedImport
            )
            end
        end

        # Now the node.
        class UseDecl < Node
            getter items : Array(UseItem)

            def initialize(@items : Array(UseItem), location : Location? = nil)
                super(location)
            end

            def accept(visitor)
                # no op
            end

            def to_source : String
                return "use " + items.map { |it|
                    case it.kind
                    when UseItemKind::Paths
                        it.specs.map(&.inspect).join(", ")
                    when UseItemKind::From
                        "{ " + it.imports.map(&.to_source).join(", ") + " } from " + it.from.not_nil!.inspect
                    end
                }.join(", ")
            end
        end
    end
end