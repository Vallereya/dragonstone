# ---------------------------------
# ------------- MAIN --------------
# --------- Orchestrator ----------
# ---------------------------------
require "./version"
require "./dragonstone/lib/**"

module Dragonstone
    PATH_SEPARATOR = {% if flag?(:windows) %} ';' {% else %} ':' {% end %}

    record RunResult, 
    tokens : Array(Token), 
    ast : AST::Program, 
    output : String

    def self.run_file(
            filename : String, 
            log_to_stdout : Bool = false
        ) : RunResult

        source = File.read(filename)
        lexer = Lexer.new(source, source_name: filename)
        tokens = lexer.tokenize

        entry_path = File.realpath(filename)
        resolver = build_resolver(entry_path)
        resolver.resolve(filename)

        ast = resolver.cache.get(entry_path) || Parser.new(tokens).parse

        runtime = Runtime::Engine.new(resolver, log_to_stdout: log_to_stdout)
        unit = runtime.compile_or_eval(ast, entry_path)
        runtime.unit_cache[entry_path] = unit

        RunResult.new(tokens, ast, unit.interpreter.output)
    end

    def self.run(
            source : String, 
            log_to_stdout : Bool = false, 
            source_name : String = "<source>"
        ) : RunResult

        lexer = Lexer.new(source, source_name: source_name)
        tokens = lexer.tokenize

        parser = Parser.new(tokens)
        ast = parser.parse

        interpreter = Interpreter.new(log_to_stdout: log_to_stdout)
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
end
