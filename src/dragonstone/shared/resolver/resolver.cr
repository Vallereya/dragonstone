# ---------------------------------
# ----------- Resolver ------------
# ---------------------------------
require "file_utils"
require "http/client"
require "socket"
require "uri"

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
        getter typed : Bool

        def initialize(@canonical_path : String, @ast : AST::Program? = nil, @typed : Bool = false)
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

        def base_directory(path : String) : String
            remote_path?(path) ? remote_directory_name(path) : File.dirname(path)
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

            normalized = read_source(path)
            processed_source, typed = Dragonstone.process_typed_directive(normalized.data)
            ast = parse(processed_source, path)
            node = ModuleNode.new(path, ast, typed)
            graph.add(node)
            cache.set(path, ast)

            base_dir = base_directory(path)

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
            if remote_path?(p)
                return p
            end
            unless File.file?(p) && File.extname(p) == config.file_ext
                raise "Module not found: #{spec} (resolved to #{p})"
            end
            p
        end

        private def expand_pattern(spec : String, base_dir : String) : Array(String)
            if remote_path?(spec) || remote_path?(base_dir)
                if spec.includes?("*")
                    raise "Globbing is not supported for remote imports: #{spec}"
                end
                return [expand_single(spec, base_dir)]
            end
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
            return append_remote_ext_if_missing(spec) if remote_path?(spec)

            if remote_path?(base_dir)
                if spec.includes?("*")
                    raise "Globbing is not supported for remote imports: #{spec}"
                end
                return resolve_remote_spec(spec, base_dir)
            end

            if spec.starts_with?("./") || spec.starts_with?("../")
                return append_ext_if_missing(File.expand_path(spec, base_dir))
            else
                found = config.roots.compact_map do |root|
                    candidate = append_ext_if_missing(File.expand_path(spec, root))
                    if candidate.includes?("*") || File.file?(candidate)
                        candidate
                    end
                end.first?
                found || append_ext_if_missing(File.expand_path(spec, base_dir))
            end
        end

        private def canonicalize(path : String, base : String) : String
            File.realpath(File.expand_path(append_ext_if_missing(path), base))
        end

        private def append_ext_if_missing(path : String) : String
            return path if path.ends_with?(config.file_ext) || path.includes?("*")
            path + config.file_ext
        end

        private def append_remote_ext_if_missing(url : String) : String
            return url if url.includes?("*")
            uri = URI.parse(url)
            return url if uri.path.ends_with?(config.file_ext)
            uri.path = uri.path + config.file_ext
            uri.to_s
        rescue ex : URI::Error
            raise "Invalid remote path #{url}: #{ex.message}"
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

        private def remote_path?(value : String) : Bool
            value.starts_with?("http://") || value.starts_with?("https://")
        end

        private def remote_directory_name(url : String) : String
            uri = URI.parse(url)
            path = uri.path
            directory = File.dirname(path)
            directory = "/" if directory == "."
            directory += "/" unless directory.ends_with?("/")
            uri.path = directory
            uri.query = nil
            uri.fragment = nil
            uri.to_s
        rescue ex : URI::Error
            raise "Invalid remote path #{url}: #{ex.message}"
        end

        private def resolve_remote_spec(spec : String, base_dir : String) : String
            if remote_path?(spec)
                return append_remote_ext_if_missing(spec)
            end

            base_uri = URI.parse(base_dir)
            resolved = base_uri.resolve(spec)
            append_remote_ext_if_missing(resolved.to_s)
        rescue ex : URI::Error
            raise "Invalid remote path #{spec}: #{ex.message}"
        end

        private def read_source(path : String) : Encoding::Source
            if remote_path?(path)
                read_remote_source(path)
            else
                Encoding.read(path)
            end
        end

        private def read_remote_source(url : String) : Encoding::Source
            body = download_remote_body(url)
            stripped = Encoding::Decoding.strip_bom(body)
            Encoding::Checks.ensure_valid_utf8!(stripped.bytes, url)
            data = Encoding::Decoding.decode_utf8(stripped.bytes)
            Encoding::Source.new(url, data, Encoding::DEFAULT, stripped.bom)
        end

        private def download_remote_body(url : String) : Bytes
            response_body = HTTP::Client.get(url) do |response|
                status = response.status_code
                unless 200 <= status && status < 300
                    raise "Failed to fetch #{url}: HTTP #{status}"
                end
                response.body_io.gets_to_end
            end
            response_body.to_slice.dup
        rescue ex : IO::Error
            raise "Failed to fetch #{url}: #{ex.message}"
        rescue ex : Socket::Error
            raise "Failed to fetch #{url}: #{ex.message}"
        rescue ex : Exception
            raise "Failed to fetch #{url}: #{ex.message}"
        end
    end
end
