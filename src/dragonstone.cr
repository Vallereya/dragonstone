# ---------------------------------
# ------------- MAIN --------------
# --------- Orchestrator ----------
# ---------------------------------
require "./version"
require "./dragonstone/backend_mode"
require "./dragonstone/shared/ir/conversion"
require "./dragonstone/shared/ir/lowering"
require "./dragonstone/shared/language/directives/directives"
require "./dragonstone/shared/language/lexer/lexer"
require "./dragonstone/shared/language/parser/parser"
require "./dragonstone/shared/language/resolver/resolver"
require "./dragonstone/shared/language/sema/type_checker"
require "./dragonstone/hybrid/runtime_engine"
require "./dragonstone/native/interpreter/interpreter"

module Dragonstone
    PATH_SEPARATOR = {% if flag?(:windows) %} ';' {% else %} ':' {% end %}
    BACKEND_ENV_KEY = "DRAGONSTONE_BACKEND"

    record RunResult, tokens : Array(Token), ast : AST::Program, output : String

    def self.run_file(filename : String, log_to_stdout : Bool = false, typed : Bool = false, backend : BackendMode? = nil) : RunResult
        backend_mode = resolve_backend_mode(backend)
        source = File.read(filename)
        processed_source, directive_typed = Language::Directives.process_typed_directive(source)
        typed ||= directive_typed
        lexer = Lexer.new(processed_source, source_name: filename)
        tokens = lexer.tokenize
        entry_path = File.realpath(filename)
        resolver = build_resolver(entry_path, backend_mode)
        resolver.resolve(filename)
        ast = resolver.cache.get(entry_path) || Parser.new(tokens).parse
        runtime = Runtime::Engine.new(resolver, log_to_stdout: log_to_stdout, typing_enabled: typed, backend_mode: backend_mode)
        analysis = Language::Sema::TypeChecker.new.analyze(ast, typed: typed)
        program = IR::Lowering.lower(ast, analysis)
        unit = runtime.compile_or_eval(program, entry_path, typed)
        runtime.unit_cache[entry_path] = unit
        RunResult.new(tokens, ast, unit.output)
    end

    def self.run(source : String, log_to_stdout : Bool = false, source_name : String = "<source>", typed : Bool = false, backend : BackendMode? = nil) : RunResult
        backend_mode = resolve_backend_mode(backend)
        processed_source, directive_typed = Language::Directives.process_typed_directive(source)
        typed ||= directive_typed
        lexer = Lexer.new(processed_source, source_name: source_name)
        tokens = lexer.tokenize
        parser = Parser.new(tokens)
        ast = parser.parse
        analysis = Language::Sema::TypeChecker.new.analyze(ast, typed: typed)
        program = IR::Lowering.lower(ast, analysis)
        inline_path = inline_source_path(source_name)
        resolver = build_resolver(inline_path, backend_mode)
        node = ModuleNode.new(inline_path, ast, typed)
        resolver.graph.add(node)
        resolver.cache.set(inline_path, ast)

        output_text = if backend_mode == BackendMode::Core
            runtime = Runtime::Engine.new(resolver, log_to_stdout: log_to_stdout, typing_enabled: typed, backend_mode: backend_mode)
            unit = runtime.compile_or_eval(program, inline_path, typed)
            runtime.unit_cache[inline_path] = unit
            unit.output
        else
            interpreter = Interpreter.new(log_to_stdout: log_to_stdout, typing_enabled: typed)
            interpreter.interpret(program, resolver.graph)
        end

        RunResult.new(tokens, ast, output_text)
    end

    def self.build_resolver(entry_path : String, backend_mode : BackendMode) : ModuleResolver
        roots = build_module_roots(entry_path)
        ModuleResolver.new(ModuleConfig.new(roots, backend_mode: backend_mode))
    end

    private def self.build_module_roots(entry_path : String) : Array(String)
        roots = [] of String
        roots << File.dirname(entry_path)

        if ds_path = ENV["DS_PATH"]?
            ds_path.split(PATH_SEPARATOR).each do |segment|
                next if segment.empty?
                roots << File.expand_path(segment)
            end
        end

        if default_root = default_stdlib_root
            roots << default_root
        end

        roots << Dir.current
        roots.uniq
    end

    private def self.default_stdlib_root : String?
        root = File.expand_path("./dragonstone/stdlib", __DIR__)
        File.directory?(root) ? root : nil
    end

    private def self.resolve_backend_mode(preferred : BackendMode?) : BackendMode
        return preferred if preferred
        backend_mode_from_env
    end

    private def self.backend_mode_from_env : BackendMode
        raw = ENV[BACKEND_ENV_KEY]?
        return BackendMode::Auto unless raw
        BackendMode.parse(raw)
    rescue ex : ArgumentError
        raise RuntimeError.new(
            "Invalid backend '#{raw}' from #{BACKEND_ENV_KEY}",
            hint: "Use auto, native, or core."
        )
    end

    private def self.inline_source_path(source_name : String) : String
        candidate = source_name == "<source>" ? "__inline__.ds" : source_name
        File.expand_path(candidate, Dir.current)
    end
end
