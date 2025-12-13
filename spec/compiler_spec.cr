require "spec"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/parser/parser"
require "../src/dragonstone/shared/language/sema/type_checker"
require "../src/dragonstone/shared/ir/program"
require "../src/dragonstone/core/compiler/compiler"

private def build_ir(ast : Dragonstone::AST::Program) : Dragonstone::IR::Program
    checker = Dragonstone::Language::Sema::TypeChecker.new
    analysis = checker.analyze(ast)
    Dragonstone::IR::Program.new(ast, analysis)
end

private def compile_bytecode(ast : Dragonstone::AST::Program) : Dragonstone::CompiledCode
    program = build_ir(ast)
    artifact = Dragonstone::Core::Compiler.build(program)
    artifact.bytecode.not_nil!
end

describe Dragonstone::Core::Compiler do
    it "compiles function parameters as indexed consts" do
        source = "def foo(a, b)\nend"
        tokens = Dragonstone::Lexer.new(source).tokenize
        ast = Dragonstone::Parser.new(tokens).parse
        bytecode = compile_bytecode(ast)

        signatures = bytecode.consts.compact_map do |const|
            const.as?(Dragonstone::Bytecode::FunctionSignature)
        end

        found = signatures.any? do |signature|
            signature.parameters.size == 2 &&
                signature.parameters.map { |param| bytecode.names[param.name_index] } == ["a", "b"]
        end

        found.should be_true
    end

    it "compiles simple assignment without dynamic symbols" do
        source = "x = 1 + 2"
        tokens = Dragonstone::Lexer.new(source).tokenize
        ast = Dragonstone::Parser.new(tokens).parse
        bytecode = compile_bytecode(ast)
        bytecode.names.should contain("x")
    end
end
