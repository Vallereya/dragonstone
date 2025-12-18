require "spec"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/parser/parser"
require "../src/dragonstone/shared/language/sema/type_checker"
require "../src/dragonstone/shared/ir/program"
require "../src/dragonstone/core/compiler/compiler"
require "../src/dragonstone/core/vm/vm"

private def compile_bytecode(source : String) : Dragonstone::CompiledCode
    tokens = Dragonstone::Lexer.new(source).tokenize
    ast = Dragonstone::Parser.new(tokens).parse
    checker = Dragonstone::Language::Sema::TypeChecker.new
    analysis = checker.analyze(ast)
    program = Dragonstone::IR::Program.new(ast, analysis)
    artifact = Dragonstone::Core::Compiler.build(program)
    artifact.bytecode.not_nil!
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

    it "exposes argv keyword" do
        source = "echo argv\n"
        bytecode = compile_bytecode(source)
        output = IO::Memory.new
        vm = Dragonstone::VM.new(bytecode, argv: ["one", "two"], stdout_io: output)

        vm.run

        output.to_s.should eq("[one, two]\n")
    end

    it "supports Array#empty? in the core backend" do
        source = "echo argv.empty?\n"
        bytecode = compile_bytecode(source)
        output = IO::Memory.new
        vm = Dragonstone::VM.new(bytecode, argv: ["one"], stdout_io: output)

        vm.run

        output.to_s.should eq("false\n")
    end

    it "rejects instantiation when abstract methods are not implemented" do
        source = <<-'DS'
        abstract class Animal
            abstract def speak
            end
        end

        class Cat < Animal
        end

        Cat.new
        DS

        bytecode = compile_bytecode(source)
        vm = Dragonstone::VM.new(bytecode)

        expect_raises(Dragonstone::TypeError) do
            vm.run
        end
    end
end
