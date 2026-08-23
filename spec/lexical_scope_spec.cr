require "spec"
require "file_utils"
require "../src/dragonstone"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/parser/parser"
require "../src/dragonstone/shared/language/sema/type_checker"
require "../src/dragonstone/shared/ir/program"
require "../src/dragonstone/core/compiler/compiler"
require "../src/dragonstone/core/vm/vm"

private def run_on_vm(source : String) : String
    tokens = Dragonstone::Lexer.new(source).tokenize
    ast = Dragonstone::Parser.new(tokens).parse
    checker = Dragonstone::Language::Sema::TypeChecker.new
    analysis = checker.analyze(ast)
    program = Dragonstone::IR::Program.new(ast, analysis)
    bytecode = Dragonstone::Core::Compiler.build(program).bytecode.not_nil!

    output = IO::Memory.new
    Dragonstone::VM.new(bytecode, stdout_io: output).run
    output.to_s
end

private def both_backends(source : String, expected : String)
    Dragonstone.run(source).output.should eq(expected)
    run_on_vm(source).should eq(expected)
end

# Runs `entry` with the other files in a temporary directory so that `use`
# exercises the normal module-resolution and import paths.
private def run_with_imports(files : Hash(String, String), entry : String) : String
    dir = File.join("bin", "dev", "build", "spec", "lexical_scope_#{Random::Secure.hex(8)}")
    FileUtils.mkdir_p(dir)

    begin
        files.each do |name, contents|
            File.write(File.join(dir, name), contents)
        end
        output = IO::Memory.new
        Dragonstone.run_file(File.join(dir, entry), output: output)
        output.to_s
    ensure
        FileUtils.rm_rf(dir)
    end
end

# The container stack tracks only the container currently executing. When a
# method of `Outer::Main` runs, the stack contains `Main`, but not its parent
# container, `Outer`.
#
# As a result, a bare reference to a sibling such as `Util` could not be
# resolved, even though the fully qualified `Outer::Util` worked. This made
# the issue appear to be missing sibling lookup support, when resolution was
# actually stopping one container level too early.
describe "lexical scope" do
    describe "sibling references" do
        it "resolves a sibling module from inside a class" do
            source = <<-DS
            module Outer
                module Util
                    extend self
                    def tag
                        return "util"
                    end
                end

                class Main
                    def initialize
                    end
                    def go
                        return Util.tag
                    end
                end
            end
            echo Outer::Main.new.go
            DS
            both_backends(source + "\n", "util\n")
        end

        it "resolves a sibling module from inside another module" do
            source = <<-DS
            module Outer
                module Util
                    extend self
                    def tag
                        return "util"
                    end
                end

                module Caller
                    extend self
                    def go
                        return Util.tag
                    end
                end
            end
            echo Outer::Caller.go
            DS
            both_backends(source + "\n", "util\n")
        end

        it "resolves an enclosing constant from inside a nested class" do
            source = <<-DS
            module Outer
                con LIMIT = 7
                class Main
                    def initialize
                    end
                    def go
                        return LIMIT
                    end
                end
            end
            echo Outer::Main.new.go
            DS
            both_backends(source + "\n", "7\n")
        end

        it "reaches out through more than one level of nesting" do
            source = <<-DS
            module App
                con LIMIT = 7
                module Util
                    extend self
                    def tag
                        return "util"
                    end
                end
                module Deep
                    module Inner
                        extend self
                        def reach_const
                            return LIMIT
                        end
                        def reach_sibling
                            return Util.tag
                        end
                    end
                end
            end
            echo App::Deep::Inner.reach_const
            echo App::Deep::Inner.reach_sibling
            DS
            both_backends(source + "\n", "7\nutil\n")
        end

        it "still resolves a fully-qualified path" do
            source = <<-DS
            module Outer
                module Util
                    extend self
                    def tag
                        return "util"
                    end
                end
                class Main
                    def initialize
                    end
                    def go
                        return Outer::Util.tag
                    end
                end
            end
            echo Outer::Main.new.go
            DS
            both_backends(source + "\n", "util\n")
        end
    end

    # Each imported file is evaluated in its own `Unit` and therefore its own
    # `Interpreter`. Singleton methods are stored in a table keyed by object
    # identity, but that table was previously scoped to a single interpreter.
    #
    # As a result, a `def self.x` declaration in an imported file was registered
    # in the imported file's interpreter and was no longer available afterward.
    # Regular `define x` methods were unaffected, making this appear to be a
    # module issue rather than an import-related one.
    describe "singleton methods across an import" do
        it "keeps def self.x callable after the module is imported" do
            output = run_with_imports({
                "lib.ds" => <<-'DS',
                module Lib
                    con TAG = "tag"
                    def self.shout(text: str): str
                        return "#{text}!"
                    end
                    define plain(text: str): str
                        return text
                    end
                end
                DS
                "main.ds" => <<-DS,
                use "./lib"
                echo Lib::TAG
                echo Lib.plain("plain")
                echo Lib.shout("shout")
                DS
            }, "main.ds")

            output.should eq("tag\nplain\nshout!\n")
        end

        it "keeps def self.x callable on a nested module" do
            output = run_with_imports({
                "nested.ds" => <<-DS,
                module Outer
                    module Inner
                        def self.reach: str
                            return "reached"
                        end
                    end
                end
                DS
                "main.ds" => <<-DS,
                use "./nested"
                echo Outer::Inner.reach
                DS
            }, "main.ds")

            output.should eq("reached\n")
        end
    end
end
