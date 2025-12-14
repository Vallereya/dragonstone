# ---------------------------------
# ----------- Loader --------------
# ---------------------------------
require "../../../backend_mode"

module Dragonstone
  # Forward declare Runtime::Engine so Importer type annotations compile
  module Runtime
    class Engine
    end
  end

  class Importer
    @runtime : Runtime::Engine

    def initialize(@resolver : ModuleResolver, @runtime : Runtime::Engine)
    end

    def apply_imports(current_unit, use_decl : AST::UseDecl, base_file : String)
      base_dir = @resolver.base_directory(base_file)
      preferred_backend = current_unit.backend.backend_mode
      use_decl.items.each do |item|
        case item.kind
        when AST::UseItemKind::Paths
          @resolver.expand_use_item(item, base_dir).each do |path|
            unit = load_unit(path, preferred_backend)
            current_unit.bind_namespace(unit.default_namespace)
          end
        when AST::UseItemKind::From
          path = @resolver.expand_use_item(item, base_dir).first
          unit = load_unit(path, preferred_backend)
          item.imports.each do |ni|
            value = unit.exported_lookup(ni.name) || raise "Symbol `#{ni.name}` not exported by #{path}"
            current_unit.bind(ni.alias_name || ni.name, value)
          end
        end
      end
    end

    private def load_unit(path : String, preferred_backend : BackendMode)
      if u = @runtime.unit_cache[{path, preferred_backend}]?
        return u
      end
      ast = @resolver.cache.get(path) || raise "Internal: missing AST for #{path}"
      unit = @runtime.compile_or_eval(ast, path, preferred_backend: preferred_backend)
      @runtime.unit_cache[{path, preferred_backend}] = unit
      @runtime.unit_cache[{path, unit.backend.backend_mode}] = unit
      unit
    end
  end
end
