require "spec"
require "../src/dragonstone"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/parser/parser"

private def parse(source : String, name : String = "<spec>")
    Dragonstone::Parser.new(Dragonstone::Lexer.new(source, name).tokenize).parse
end

# `to_source` round-trip test: render a statement, then parse the rendered
# source again.
#
# This verifies more than whether `to_source(io)` completes without raising.
# A renderer can produce output successfully even when that output is not valid
# Dragonstone source. The following renderers had that problem:
#
# - `class`, `module`, and `def` bodies were joined with `"; "`. Dragonstone
#   has no semicolon statement separator, so the generated source could not be
#   parsed again.
# - `with` expressions rendered as `with x do ... end`, but Dragonstone syntax
#   requires `with x`, followed by the body on subsequent lines, then `end`.
# - Map literals rendered as `{"k": 1}` instead of `{ "k" -> 1 }`.
# - Compound assignments rendered as `x + = 1` instead of `x += 1`.
#
# Each renderer completed without error while producing invalid source. The
# round-trip test detects these failures by requiring the rendered output to
# parse successfully.
#
# Correct rendering is required for more than source formatting:
#
# - `normalized_source` is embedded directly in generated C, LLVM, Crystal,
#   Ruby, Python, and JavaScript artifacts.
# - `e!` stores rendered source in the bytecode constant pool.
# - `LexicalBindings` reparses and rerenders interpolated expressions on both
#   backends.
#
# Invalid output therefore creates incorrect generated artifacts; it is not
# merely a formatting issue.
private def assert_round_trips(source : String)
    ast = parse(source)

    ast.statements.each do |stmt|
        rendered = stmt.to_source

        begin
            parse(rendered, "<rendered>")
        rescue ex
            fail "#{stmt.class} rendered as #{rendered.inspect}, which does not parse back: #{ex.message}"
        end
    end
end

describe "to_source round-trip" do
    # Includes one example for each AST node shape. If a shape is missing from this
    # list, its renderer is not covered—add a case whenever a renderer is added or
    # changed.
    {
        "assignment"            => "x = 1\n",
        "typed assignment"      => "x : int = 1\n",
        "compound assignment"   => "x = 1\nx += 2\n",
        "constant"              => "con LIMIT : int = 10\n",
        "alias"                 => "alias MyInt = int\n",
        "array literal"         => "xs = [1, 2]\n",
        "tuple literal"         => "t = {1, 2}\n",
        "named tuple"           => "n = { a: 1 }\n",
        "map literal"           => "m = { \"k\" -> 1 }\n",
        "index assignment"      => "xs = [1]\nxs[0] = 9\n",
        "bag constructor"       => "b = bag(str)\n",
        "conditional"           => "c = true ? 1 : 2\n",
        "unary"                 => "x = 1\nu = -x\n",
        "binary"                => "x = 1 + 2 * 3\n",
        "interpolation"         => "x = 1\necho \"v=\#{x}\"\n",
        "if/elsif/else"         => "if 1 > 2\n    echo \"a\"\nelsif 1 > 0\n    echo \"b\"\nelse\n    echo \"c\"\nend\n",
        "unless"                => "unless 1 > 2\n    echo \"u\"\nend\n",
        "while"                 => "x = 0\nwhile x < 3\n    x += 1\nend\n",
        "case"                  => "x = 1\ncase x\nwhen 1\n    echo \"one\"\nelse\n    echo \"other\"\nend\n",
        "begin/rescue/ensure"   => "begin\n    echo \"t\"\nrescue e\n    echo \"r\"\nensure\n    echo \"en\"\nend\n",
        "rescue with type"      => "begin\n    echo \"t\"\nrescue e: Exception\n    echo \"r\"\nend\n",
        "function def"          => "def f(a, b = 2) : int\n    return a + b\nend\n",
        "class"                 => "class Sq\n    def area : int\n        return 1\n    end\nend\n",
        "abstract class"        => "abstract class Shape\n    abstract def area : int\n    end\nend\n",
        "module"                => "module M\n    extend self\n    def g\n        yield 1\n    end\nend\n",
        "struct"                => "struct Pt\n    getter px : int\nend\n",
        "enum"                  => "enum Color\n    Red\n    Blue\nend\n",
        "extend"                => "extend Comparable\n",
        "instance var"          => "class C\n    def initialize\n        @iv = 4\n        @iv += 1\n    end\nend\n",
        "instance var decl"     => "class C\n    @iv : str\nend\n",
        "para literal"          => "p = ->(v) { v + 1 }\n",
        "fun literal"           => "fn = fun (v) v * 2 end\n",
        # Uses multi-statement bodies. Single-statement cases hid the `"; "` joining
        # bug because no separator is needed when a body contains only one statement.
        "para literal, 2 stmts" => "p = ->(v) {\n    a = v + 1\n    a * 2\n}\n",
        "fun literal, 2 stmts"  => "fn = fun (v)\n    a = v + 1\n    a * 2\nend\n",
        "block literal, 2 stmts" => "[1].each do |v|\n    a = v + 1\n    echo a\nend\n",
        "with"                  => "x = 1\nwith x\n    echo \"w\"\nend\n",
        "raise"                 => "raise \"boom\"\n",
        "quit"                  => "quit 0\n",
        "return"                => "def f\n    return\nend\n",
    }.each do |name, source|
        it "round-trips #{name}" do
            assert_round_trips(source)
        end
    end

    # Renders the full corpus together, including nested expressions. Several of
    # the issues above appeared only when a node was rendered inside another node.
    it "round-trips every shape together" do
        assert_round_trips(File.read(File.join(__DIR__, "fixtures", "to_source_shapes.ds")))
    end

    # A round-trip test is necessary but not sufficient: rendered source can parse
    # successfully while still changing the program's meaning.
    #
    # `break`, `next`, `redo`, and `retry` previously always rendered `" if "`,
    # ignoring `condition_type`. As a result, `next unless x` rendered as
    # `next if x`: valid Dragonstone syntax with the opposite behavior.
    #
    # Parsing the result again cannot detect this kind of error, so these cases
    # assert the exact rendered text.
    describe "statement modifiers keep their keyword" do
        {
            "break"  => "while true\n    break unless 1 > 2\nend\n",
            "next"   => "while true\n    next unless 1 > 2\nend\n",
            "redo"   => "while true\n    redo unless 1 > 2\nend\n",
            "retry"  => "begin\n    echo \"x\"\nrescue e\n    retry unless 1 > 2\nend\n",
        }.each do |keyword, source|
            it "renders #{keyword} unless, not #{keyword} if" do
                rendered = parse(source).statements.map(&.to_source).join("\n")
                rendered.should contain("#{keyword} unless")
                rendered.should_not contain("#{keyword} if")
            end
        end
    end
end
