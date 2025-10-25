# ---------------------------------
# ------------- MAIN --------------
# --------- Orchestrator ----------
# ---------------------------------
require "./version"
require "./dragonstone/lib/**"

module Dragonstone
    record RunResult, 
    tokens : Array(Token), 
    ast : AST::Program, 
    output : String

    def self.run_file(
            filename : String, 
            log_to_stdout : Bool = false
        ) : RunResult

        source = File.read(filename)

        run(source, 
            log_to_stdout: log_to_stdout, 
            source_name: filename
        )
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
end
