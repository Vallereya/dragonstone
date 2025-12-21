# ---------------------------------
# ----------- Resolver ------------
# ---------------------------------
require "../../../backend_mode"
require "file_utils"
require "http/client"
require "socket"
require "uri"
require "../directives/directives"
require "./module_metadata"

module Dragonstone
  class ModuleGraph
    getter nodes : Hash(String, ModuleNode) = {} of String => ModuleNode

    def add(node : ModuleNode)
      nodes[node.canonical_path] = node
    end

    def [](path : String)
      nodes[path]?
    end

    def []?(path : String)
      nodes[path]?
    end
  end

  class ModuleNode
    getter canonical_path : String
    getter ast : AST::Program?
    getter deps : Array(String) = [] of String
    getter typed : Bool
    getter metadata : Stdlib::ModuleMetadata?

    def initialize(
      @canonical_path : String,
      @ast : AST::Program? = nil,
      @typed : Bool = false,
      @metadata : Stdlib::ModuleMetadata? = nil
    )
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
    getter roots : Array(String) # search roots (project root, stdlib root, etc.)
    getter allow_globs : Bool
    getter file_ext : String # ".ds"
    getter backend_mode : BackendMode

    def initialize(
      @roots : Array(String),
      *,
      file_ext : String = ".ds",
      allow_globs : Bool = true,
      backend_mode : BackendMode = BackendMode::Auto
    )
      @file_ext = file_ext
      @allow_globs = allow_globs
      @backend_mode = backend_mode
    end
  end

  class ModuleResolver
    getter config : ModuleConfig
    getter cache : ModuleCache
    getter graph : ModuleGraph

    @metadata_cache : Hash(String, Stdlib::ModuleMetadata)

    def initialize(@config : ModuleConfig, @cache = ModuleCache.new, @graph = ModuleGraph.new)
      @metadata_cache = {} of String => Stdlib::ModuleMetadata
    end

    # Resolve all `use` directives reachable from `entry_path`,
    # then returns a topo sorted list of canonical file paths.
    def resolve(entry_path : String) : Array(String)
      if remote_path?(entry_path)
        visit_remote(entry_path, parents: [] of String)
      else
        entry = canonicalize(entry_path, base: Dir.current)
        visit(entry, parents: [] of String)
      end
      topo_sort
    end

    def base_directory(path : String) : String
      remote_path?(path) ? remote_directory_name(path) : File.dirname(path)
    end

    # Expand a UseItem into concrete file paths.
    def expand_use_item(item : AST::UseItem, base_dir : String, exclude_path : String? = nil) : Array(String)
      case item.kind
      when AST::UseItemKind::Paths
        paths = item.specs.flat_map { |spec| expand_pattern(spec, base_dir, exclude_path) }.uniq
        exclude_path ? paths.reject { |p| p == exclude_path } : paths
      when AST::UseItemKind::From
        path = expand_single(item.from.not_nil!, base_dir, exclude_path)
        exclude_path && path == exclude_path ? [] of String : [path]
      else
        raise "Unknown use item kind: #{item.kind}"
      end
    end

    private def visit(path : String, parents : Array(String))
      raise "Cyclic import: #{(parents + [path]).join(" -> ")}" if parents.includes?(path)
      return if graph[path]

      normalized = read_source(path)
      processed_source, typed = Language::Directives.process_typed_directive(normalized.data)
      ast = parse(processed_source, path)
      metadata = metadata_for_entry(path)
      ensure_metadata_supports_backend!(metadata) if metadata
      node = ModuleNode.new(path, ast, typed, metadata)
      graph.add(node)
      cache.set(path, ast)

      base_dir = base_directory(path)

      depend_paths = ast.use_decls.flat_map do |use_decl|
        use_decl.items.flat_map { |item| expand_use_item(item, base_dir, exclude_path: path) }
      end.reject { |dep| dep == path }.uniq

      depend_paths.each do |dep|
        graph[path].not_nil!.deps << dep
        if remote_path?(dep)
          visit_remote(dep, parents + [path])
        else
          visit(dep, parents + [path])
        end
      end
    end

    private def visit_remote(url : String, parents : Array(String))
      raise "Cyclic import: #{(parents + [url]).join(" -> ")}" if parents.includes?(url)
      return if graph[url]

      source_path = local_fallback_for_remote(url) || url
      normalized = read_source(source_path)
      processed_source, typed = Language::Directives.process_typed_directive(normalized.data)
      ast = parse(processed_source, source_path)
      node = ModuleNode.new(url, ast, typed, nil)
      graph.add(node)
      cache.set(url, ast)

      base_dir = base_directory(source_path)

      depend_paths = ast.use_decls.flat_map do |use_decl|
        use_decl.items.flat_map { |item| expand_use_item(item, base_dir, exclude_path: url) }
      end.reject { |dep| dep == url }.uniq

      depend_paths.each do |dep|
        graph[url].not_nil!.deps << dep
        if remote_path?(dep)
          visit_remote(dep, parents + [url])
        else
          visit(dep, parents + [url])
        end
      end
    end

    # Makes sure it has .ds extension
    private def expand_single(spec : String, base_dir : String, exclude_path : String? = nil) : String
      p = resolve_spec(spec, base_dir, exclude_path)
      if remote_path?(p)
        return p
      end
      unless File.file?(p) && File.extname(p) == config.file_ext
        raise "Module not found: #{spec} (resolved to #{p})"
      end
      p
    end

    private def expand_pattern(spec : String, base_dir : String, exclude_path : String? = nil) : Array(String)
      if remote_path?(spec) || remote_path?(base_dir)
        if spec.includes?("*")
          raise "Globbing is not supported for remote imports: #{spec}"
        end
        path = expand_single(spec, base_dir, exclude_path)
        return exclude_path && path == exclude_path ? [] of String : [path]
      end
      p = resolve_spec(spec, base_dir, exclude_path)
      if p.includes?("*")
        Dir.glob(p)
          .select { |f| File.file?(f) && File.extname(f) == config.file_ext }
          .map { |f| canonicalize(f, base: base_dir) }
      else
        path = expand_single(spec, base_dir, exclude_path)
        exclude_path && path == exclude_path ? [] of String : [path]
      end
    end

    # "./**" -> "<base_dir>/**/*.ds", "../folder/*" -> "<resolved>/*"
    private def resolve_spec(spec : String, base_dir : String, exclude_path : String? = nil) : String
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
          if exclude_path && !candidate.includes?("*") && File.file?(candidate)
            begin
              next if File.realpath(candidate) == exclude_path
            rescue
              # ignore; treat as non-excluded
            end
          end
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

    private def metadata_for_entry(path : String) : Stdlib::ModuleMetadata?
      return nil if remote_path?(path)
      metadata_path = Stdlib::ModuleMetadata.metadata_path_for_entry(path)
      return nil unless metadata_path
      metadata = @metadata_cache[metadata_path]?
      return metadata if metadata
      loaded = Stdlib::ModuleMetadata.load(metadata_path)
      @metadata_cache[metadata_path] = loaded
      loaded
    end

    private def ensure_metadata_supports_backend!(metadata : Stdlib::ModuleMetadata)
      backend = config.backend_mode
      return if backend == BackendMode::Auto
      return if metadata.supports_backend?(backend)
      raise RuntimeError.new(
        "Stdlib module #{metadata.name} requires #{metadata.requirement.label} features, incompatible with #{backend.label} backend.",
        hint: "Switch backends or remove the import."
      )
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
      if fallback_path = local_fallback_for_remote(url)
        return Encoding.read(fallback_path)
      end

      begin
        body = download_remote_body(url)
        stripped = Encoding::Decoding.strip_bom(body)
        Encoding::Checks.ensure_valid_utf8!(stripped.bytes, url)
        data = Encoding::Decoding.decode_utf8(stripped.bytes)
        return Encoding::Source.new(url, data, Encoding::DEFAULT, stripped.bom)
      rescue ex : Exception
        if fallback_path = local_fallback_for_remote(url)
          return Encoding.read(fallback_path)
        end
        raise ex
      end
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

    private def local_fallback_for_remote(url : String) : String?
      # If network is unavailable, try to map well-known repo URLs back to local files.
      begin
        uri = URI.parse(url)
        path = uri.path
        roots = config.roots
        candidates = [] of String

        if m = path.match(/dragonstone@[^\/]*\/(.*)/)
          candidates << m[1]
        end

        if m = path.match(/\/examples\/.*$/)
          candidates << m[0].lstrip('/')
        end

        search_roots = roots.empty? ? [Dir.current] : roots
        search_roots.each do |root|
          candidates.each do |suffix|
            candidate = File.join(root, suffix)
            return candidate if File.file?(candidate)
          end
        end
      rescue
        # ignore
      end
      nil
    end
  end
end
