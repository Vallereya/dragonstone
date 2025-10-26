# ---------------------------------
# ----------- Resolver ------------
# ---------------------------------
require "file_utils"

module Dragonstone
    class ModuleGraph
        getter nodes : Hash(String, ModuleNode) = {} of String => ModuleNode

        def add(node : ModuleNode)
            nodes[node.canonical_path] = node
        end

        def [](path : String)
            nodes[path]?
        end
    end

    class ModuleNode
        getter canonical_path : String
        getter ast : AST::Program?
        getter deps : Array(String) = [] of String

        def initialize(@canonical_path : String, @ast : AST::Program? = nil)
        end
    end

    class ModuleCache
        getter ast_by_path : Hash(String, AST::Program) = {} of String => AST::Program

        def get(path : String) : AST::Program?
            ast_by_path[path]?
        end

        def set(path : String, ast : AST::Program)
            ast_by_path[path] = ast
        end
    end

    # Configuration (can also read DS_PATH env).
    struct ModuleConfig
        getter roots : Array(String)           # search roots (project root, stdlib root, etc.)
        getter allow_globs : Bool
        getter file_ext : String               # ".ds"

        def initialize(@roots : Array(String), @file_ext = ".ds", @allow_globs = true)
        end
    end

    class ModuleResolver
        getter config : ModuleConfig
        getter cache  : ModuleCache
        getter graph  : ModuleGraph

        def initialize(@config : ModuleConfig, @cache = ModuleCache.new, @graph = ModuleGraph.new)
        end

        # Resolve all `use` directives reachable from `entry_path`,
        # then returns a topo sorted list of canonical file paths.
        def resolve(entry_path : String) : Array(String)
            entry = canonicalize(entry_path, base: Dir.current)
            visit(entry, parents: [] of String)
            topo_sort
        end

        # Expand a UseItem into concrete file paths.
        def expand_use_item(item : AST::UseItem, base_dir : String) : Array(String)
            case item.kind

            when AST::UseItemKind::Paths
                item.specs.flat_map { |spec| expand_pattern(spec, base_dir) }.uniq

            when AST::UseItemKind::From
                [ expand_single(item.from.not_nil!, base_dir) ]

            else
                raise "Unknown use item kind: #{item.kind}"

            end
        end

        private def visit(path : String, parents : Array(String))
            return if graph[path]
            raise "Cyclic import: #{(parents + [path]).join(" -> ")}" if parents.includes?(path)

            normalized = Encoding.read(path)
            ast = parse(normalized.data, path)
            graph.add(ModuleNode.new(path, ast))
            cache.set(path, ast)

            base_dir = File.dirname(path)

            depend_paths = ast.use_decls.flat_map do |use_decl|
                use_decl.items.flat_map { |item| expand_use_item(item, base_dir) }
            end.uniq

            depend_paths.each do |dep|
                graph[path].not_nil!.deps << dep
                visit(dep, parents + [path])
            end
        end

        # Makes sure it has .ds extension
        private def expand_single(spec : String, base_dir : String) : String
            p = resolve_spec(spec, base_dir)
            unless File.file?(p) && File.extname(p) == config.file_ext
                raise "Module not found: #{spec} (resolved to #{p})"
            end
            p
        end

        private def expand_pattern(spec : String, base_dir : String) : Array(String)
            p = resolve_spec(spec, base_dir)
            if p.includes?("*")
                Dir.glob(p)
                .select { |f| File.file?(f) && File.extname(f) == config.file_ext }
                .map { |f| canonicalize(f, base: base_dir) }
            else
                [expand_single(spec, base_dir)]
            end
        end

        # "./**" -> "<base_dir>/**/*.ds", "../folder/*" -> "<resolved>/*"
        private def resolve_spec(spec : String, base_dir : String) : String
            if spec.starts_with?("./") || spec.starts_with?("../")
                joined = File.expand_path(spec, base_dir)
                joined
            else
                found = config.roots.compact_map do |root|
                    path = File.expand_path(spec, root)
                    File.exists?(path) ? path : nil
                end.first?
                found || File.expand_path(spec, base_dir)
            end
        end

        private def canonicalize(path : String, base : String) : String
            File.realpath(File.expand_path(append_ext_if_missing(path), base))
        end

        private def append_ext_if_missing(path : String) : String
            return path if path.ends_with?(config.file_ext) || path.includes?("*")
            path + config.file_ext
        end

        private def topo_sort : Array(String)
            indeg = Hash(String, Int32).new { 0 }
            graph.nodes.each_value do |n|
                indeg[n.canonical_path] = indeg[n.canonical_path] # ensure key
                n.deps.each { |d| indeg[d] = indeg[d] + 1 }
            end

            q = Array(String).new
            indeg.each { |k, v| q << k if v == 0 }

            order = [] of String
            until q.empty?
                v = q.pop
                order << v
                node = graph[v].not_nil!
                node.deps.each do |d|
                    indeg[d] = indeg[d] - 1
                    q << d if indeg[d] == 0
                end
            end

            if order.size != graph.nodes.size
                raise "Import cycle (should have been caught earlier)"
            end
            order
        end

        private def parse(src : String, path : String) : AST::Program
            Dragonstone::Parser.parse(src, path)
        end
    end
end
