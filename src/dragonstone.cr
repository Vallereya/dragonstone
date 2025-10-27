# ---------------------------------
# ------------- MAIN --------------
# --------- Orchestrator ----------
# ---------------------------------
require "./version"
require "./dragonstone/lib/**"

module Dragonstone
    PATH_SEPARATOR = {% if flag?(:windows) %} ';' {% else %} ':' {% end %}
    TYPED_DIRECTIVE_PATTERN = /\A#![ \t]*typed[^\r\n]*(\r?\n)?/i

    record RunResult, 
    tokens : Array(Token), 
    ast : AST::Program, 
    output : String

    def self.run_file(
            filename : String, 
            log_to_stdout : Bool = false,
            typed : Bool = false
        ) : RunResult

        source = File.read(filename)
        processed_source, directive_typed = process_typed_directive(source)
        typed ||= directive_typed
        lexer = Lexer.new(processed_source, source_name: filename)
        tokens = lexer.tokenize

        entry_path = File.realpath(filename)
        resolver = build_resolver(entry_path)
        resolver.resolve(filename)

        ast = resolver.cache.get(entry_path) || Parser.new(tokens).parse

        runtime = Runtime::Engine.new(resolver, log_to_stdout: log_to_stdout, typing_enabled: typed)
        unit = runtime.compile_or_eval(ast, entry_path)
        runtime.unit_cache[entry_path] = unit

        RunResult.new(tokens, ast, unit.interpreter.output)
    end

    def self.run(
            source : String, 
            log_to_stdout : Bool = false, 
            source_name : String = "<source>",
            typed : Bool = false
        ) : RunResult

        processed_source, directive_typed = process_typed_directive(source)
        typed ||= directive_typed
        lexer = Lexer.new(processed_source, source_name: source_name)
        tokens = lexer.tokenize

        parser = Parser.new(tokens)
        ast = parser.parse

        interpreter = Interpreter.new(log_to_stdout: log_to_stdout, typing_enabled: typed)
        output_text = interpreter.interpret(ast)

        RunResult.new(tokens, ast, output_text)
    end

    private def self.build_resolver(entry_path : String) : ModuleResolver
        roots = build_module_roots(entry_path)
        ModuleResolver.new(ModuleConfig.new(roots))
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

        roots << Dir.current
        roots.uniq
    end

    def self.process_typed_directive(source : String) : Tuple(String, Bool)
        if match = TYPED_DIRECTIVE_PATTERN.match(source)
            newline = match[1]? || ""
            directive_length = match[0].size
            body_length = directive_length - newline.size
            replacement = " " * body_length + newline
            remainder = directive_length < source.size ? source[directive_length..-1] : ""
            {replacement + remainder, true}
        else
            {source, false}
        end
    end
end
