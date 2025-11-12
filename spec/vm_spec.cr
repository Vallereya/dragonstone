require "spec"
require "../src/dragonstone/shared/lexer/lexer"
require "../src/dragonstone/shared/parser/parser"
require "../src/dragonstone/core/compiler/compiler"
require "../src/dragonstone/shared/vm/vm"

private def compile_bytecode(source : String) : Dragonstone::CompiledCode
    tokens = Dragonstone::Lexer.new(source).tokenize
    ast = Dragonstone::Parser.new(tokens).parse
    Dragonstone::Compiler.compile(ast)
end

describe Dragonstone::VM do

    it "executes function calls and returns values" do
        source = <<-'DS'
        def add(a, b)
            return a + b
        end

        echo add(2, 3)
        DS

        bytecode = compile_bytecode(source)
        output = IO::Memory.new
        vm = Dragonstone::VM.new(bytecode, stdout_io: output)

        vm.run

        output.to_s.should eq("5\n")
    end

    it "supports nested calls and interpolation expressions" do
        source = <<-'DS'
        def shout(name)
            msg = "Hello, #{name}"
            echo msg
            return msg
        end

        echo shout("VM")
        DS

        bytecode = compile_bytecode(source)
        output = IO::Memory.new
        vm = Dragonstone::VM.new(bytecode, stdout_io: output)

        vm.run

        output.to_s.should eq("Hello, VM\nHello, VM\n")
    end

    it "prints empty line for nil echo" do
        source = "echo nil\n"
        bytecode = compile_bytecode(source)
        output = IO::Memory.new
        vm = Dragonstone::VM.new(bytecode, stdout_io: output)

        vm.run

        output.to_s.should eq("\n")
    end
end
