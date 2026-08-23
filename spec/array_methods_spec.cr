require "spec"
require "../src/dragonstone"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/parser/parser"
require "../src/dragonstone/shared/language/sema/type_checker"
require "../src/dragonstone/shared/ir/program"
require "../src/dragonstone/core/compiler/compiler"
require "../src/dragonstone/core/vm/vm"

# Runs a snippet directly on the VM, bypassing the interpreter-facing
# `Dragonstone.run` entry point.
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

# Array methods have separate implementations in the interpreter
# (`call_array_method`) and the VM (`when Array`). These implementations
# have diverged before—for example, they formatted floats differently.
#
# Each case therefore verifies that both implementations produce the
# expected output, rather than comparing one implementation against the other.
private def both_backends(source : String, expected : String)
    Dragonstone.run(source).output.should eq(expected)
    run_on_vm(source).should eq(expected)
end

describe "Array methods" do
    describe "membership" do
        it "finds elements with includes? and its aliases" do
            both_backends(
                "a = [1, 2, 3]\necho a.includes?(2)\necho a.member?(3)\necho a.contains?(9)\n",
                "true\ntrue\nfalse\n"
            )
        end

        it "returns the index of the first match, or nil" do
            both_backends(
                "a = [3, 1, 2, 1]\necho a.index(1)\necho a.index(9)\n",
                "1\n\n"
            )
        end

        it "honours a custom == when searching" do
            source = <<-DS
            class Box
                define initialize(value)
                    @value = value
                end
                define ==(other)
                    return true
                end
            end

            echo [Box.new(1)].includes?(Box.new(2))
            DS
            Dragonstone.run(source).output.should eq("true\n")
        end
    end

    describe "transforms" do
        it "drops duplicates keeping first occurrence and order" do
            both_backends("echo [3, 1, 2, 1, 3].uniq\n", "[3, 1, 2]\n")
        end

        it "drops nils with compact" do
            both_backends("echo [1, nil, 2, nil].compact\n", "[1, 2]\n")
        end

        it "reverses without mutating" do
            both_backends("a = [1, 2, 3]\necho a.reverse\necho a\n", "[3, 2, 1]\n[1, 2, 3]\n")
        end

        it "sorts numbers and strings without mutating" do
            both_backends("a = [3, 1, 2]\necho a.sort\necho a\n", "[1, 2, 3]\n[3, 1, 2]\n")
            both_backends("echo [\"b\", \"a\", \"c\"].sort\n", "[a, b, c]\n")
        end

        it "raises rather than ordering a mixed-type array arbitrarily" do
            expect_raises(Exception) { Dragonstone.run("echo [1, \"a\"].sort\n") }
        end
    end

    describe "join" do
        it "uses the separator, defaulting to empty" do
            both_backends("echo [\"a\", \"b\", \"c\"].join(\", \")\n", "a, b, c\n")
            both_backends("echo [\"a\", \"b\"].join\n", "ab\n")
        end

        it "renders elements the way echo does, not inspected" do
            both_backends("echo [1, 2].join(\"-\")\n", "1-2\n")
        end

        it "produces empty string for an empty array" do
            both_backends("echo [].join(\",\").length\n", "0\n")
        end
    end

    describe "block predicates" do
        it "answers any? / all? / none? with a block" do
            source = "a = [1, 2, 3]\n" \
                     "echo a.any? do |x| x > 2 end\n" \
                     "echo a.all? do |x| x > 0 end\n" \
                     "echo a.none? do |x| x > 9 end\n"
            both_backends(source, "true\ntrue\ntrue\n")
        end

        it "treats any? without a block as 'any truthy element', not 'not empty'" do
            both_backends("echo [nil].any?\necho [].any?\necho [1].any?\n", "false\nfalse\ntrue\n")
        end

        it "finds the first matching element, or nil" do
            both_backends(
                "a = [1, 2, 3]\necho a.find do |x| x > 1 end\necho a.find do |x| x > 9 end\n",
                "2\n\n"
            )
        end
    end

    describe "block transforms" do
        it "rejects matching elements" do
            both_backends("echo [1, 2, 3].reject do |x| x == 2 end\n", "[1, 3]\n")
        end

        it "flattens exactly one level with flat_map" do
            both_backends("echo [1, 2].flat_map do |x| [x, x] end\n", "[1, 1, 2, 2]\n")
            both_backends("echo [1].flat_map do |x| [[x]] end\n", "[[1]]\n")
        end

        it "maps and drops nils with compact_map" do
            both_backends("echo [1, 2, 3].compact_map do |x| x == 2 ? nil : x end\n", "[1, 3]\n")
        end

        it "yields element and index to each_with_index" do
            # The source array is assigned to a variable intentionally. At present,
            # a line beginning with `[` is parsed as an index expression continuing
            # from the previous line.
            source = <<-'DS'
            out = [] as str
            src = ["a", "b"]
            src.each_with_index do |x, i|
                out << "#{i}#{x}"
            end
            echo out.join(",")
            DS
            both_backends(source + "\n", "0a,1b\n")
        end
    end

    describe "count" do
        it "returns the size with no argument" do
            both_backends("echo [1, 2, 3].count\n", "3\n")
        end

        it "counts equal elements with an argument" do
            both_backends("echo [1, 2, 1].count(1)\n", "2\n")
        end

        it "counts accepted elements with a block" do
            both_backends("echo [1, 2, 3].count do |x| x > 1 end\n", "2\n")
        end
    end

    describe "mutation" do
        it "appends with << and returns the array so it chains" do
            both_backends("a = [1]\na << 2\na << 3\necho a\n", "[1, 2, 3]\n")
        end

        it "appends another array in place with concat" do
            both_backends("a = [1, 2]\na.concat([3, 4])\necho a\n", "[1, 2, 3, 4]\n")
        end

        it "rejects a non-Array argument to concat" do
            expect_raises(Exception) { Dragonstone.run("[1].concat(2)\n") }
        end
    end

    describe "nil-safe accessors" do
        it "aliases first? / last? to first / last" do
            both_backends("a = [1, 2]\necho a.first?\necho a.last?\n", "1\n2\n")
        end

        it "returns nil rather than raising on an empty array" do
            both_backends("echo [].first?.nil?\necho [].last?.nil?\n", "true\ntrue\n")
        end
    end

    it "chains the new methods together" do
        both_backends("echo [5, 3, 5, 1].uniq.sort.reverse.join(\"-\")\n", "5-3-1\n")
    end
end
