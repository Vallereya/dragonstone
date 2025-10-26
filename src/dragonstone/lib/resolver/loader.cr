# ---------------------------------
# ----------- Loader --------------
# ---------------------------------
module Dragonstone
    class Importer
        @runtime : Runtime::Engine

        def initialize(@resolver : ModuleResolver, @runtime : Runtime::Engine)
        end

        def apply_imports(current_unit, use_decl : AST::UseDecl, base_file : String)
            use_decl.items.each do |item|
                case item.kind
                when AST::UseItemKind::Paths
                    @resolver.expand_use_item(item, File.dirname(base_file)).each do |path|
                        unit = load_unit(path)
                        current_unit.bind_namespace(unit.default_namespace)
                    end
                when AST::UseItemKind::From
                    path = @resolver.expand_use_item(item, File.dirname(base_file)).first
                    unit = load_unit(path)
                    item.imports.each do |ni|
                        value = unit.exported_lookup(ni.name) || raise "Symbol `#{ni.name}` not exported by #{path}"
                        current_unit.bind(ni.alias_name || ni.name, value)
                    end
                end
            end
        end

        private def load_unit(path : String)
            if u = @runtime.unit_cache[path]?
                return u
            end
            ast = @resolver.cache.get(path) || raise "Internal: missing AST for #{path}"
            unit = @runtime.compile_or_eval(ast, path)
            @runtime.unit_cache[path] = unit
            unit
        end
    end
end
