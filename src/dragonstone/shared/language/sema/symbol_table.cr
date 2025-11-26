# ---------------------------------
# -------- Symbol Table -----------
# ---------------------------------
module Dragonstone
    module Language
        module Sema
            enum SymbolKind
                Variable
                Constant
                Function
                Type
                Module
            end

            record SymbolInfo,
                name : String,
                kind : SymbolKind,
                type_descriptor : String? = nil

            class SymbolTable
                getter symbols : Hash(String, SymbolInfo)

                def initialize
                    @symbols = {} of String => SymbolInfo
                end

                def define(name : String, kind : SymbolKind, type_descriptor : String? = nil)
                    @symbols[name] = SymbolInfo.new(name, kind, type_descriptor)
                end

                def defined?(name : String) : Bool
                    @symbols.has_key?(name)
                end

                def lookup(name : String) : SymbolInfo?
                    @symbols[name]?
                end

                def merge!(other : SymbolTable)
                    other.symbols.each do |name, info|
                        @symbols[name] = info
                    end
                end
            end
        end
    end
end
