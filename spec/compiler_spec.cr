require "spec"
require "../src/dragonstone/shared/lexer/lexer"
require "../src/dragonstone/shared/parser/parser"
require "../src/dragonstone/core/compiler/compiler"

describe Dragonstone::Compiler do
    it "compiles function parameters as indexed consts" do
        source = "def foo(a, b)\nend"
        tokens = Dragonstone::Lexer.new(source).tokenize
        ast = Dragonstone::Parser.new(tokens).parse
        bytecode = Dragonstone::Compiler.compile(ast)

        param_arrays = bytecode.consts.compact_map do |const|
            const.as?(Array(Dragonstone::Bytecode::Value))
        end

        found = param_arrays.any? do |arr|
            names = arr.map do |entry|
                index = entry.as(Int32)
                bytecode.names[index]
            end
            names == ["a", "b"]
        end

        found.should be_true
    end

    it "compiles simple assignment without dynamic symbols" do
        source = "x = 1 + 2"
        tokens = Dragonstone::Lexer.new(source).tokenize
        ast = Dragonstone::Parser.new(tokens).parse
        bytecode = Dragonstone::Compiler.compile(ast)
        bytecode.names.should contain("x")
    end
end
