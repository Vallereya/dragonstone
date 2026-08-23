require "spec"
require "file_utils"
require "../src/dragonstone"

# Reopening namespaces across files, including the frame-ownership behavior
# exercised by `bin/main.ds` when stage1 began running on the core backend.
#
# Every case in this group passed on the interpreter but failed on the VM.
private def with_files(name : String, files : Hash(String, String), &)
    dir = File.join(Dir.current, "logs", "#{name}_#{Random::Secure.hex(8)}")
    FileUtils.mkdir_p(dir)
    begin
        files.each do |relative, source|
            path = File.join(dir, relative)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, source)
        end
        yield File.join(dir, "entry.ds")
    ensure
        FileUtils.rm_rf(dir)
    end
end

private def both_backends(entry : String, expected : String)
    Dragonstone.run_file(entry, backend: Dragonstone::BackendMode::Native).output.should eq expected
    Dragonstone.run_file(entry, backend: Dragonstone::BackendMode::Core).output.should eq expected
end

describe "reopening a namespace across files" do
    # `MAKE_MODULE` reused an existing module, but imports did not. When a second
    # file defined `A`, it replaced the module created by the first file and lost
    # its constants.
    it "merges constants from every file that opens the module" do
        with_files("merge_constants", {
            "one.ds"   => "module A\n    con FIRST = \"one\"\nend\n",
            "two.ds"   => "module A\n    con SECOND = \"two\"\nend\n",
            "entry.ds" => "use \"./one\"\nuse \"./two\"\necho A::FIRST\necho A::SECOND\n",
        }) do |entry|
            both_backends(entry, "one\ntwo\n")
        end
    end

    it "merges nested modules rather than replacing them" do
        with_files("merge_nested", {
            "one.ds"   => "module A\n    module B\n        con FIRST = 1\n    end\nend\n",
            "two.ds"   => "module A\n    module B\n        con SECOND = 2\n    end\nend\n",
            "entry.ds" => "use \"./one\"\nuse \"./two\"\necho A::B::FIRST\necho A::B::SECOND\n",
        }) do |entry|
            both_backends(entry, "1\n2\n")
        end
    end

    # Singleton methods are stored in the VM by receiver identity. Because each
    # file runs in its own VM, methods defined on a module were available only in
    # the file that defined them.
    it "keeps def self.x when another file reopens the module" do
        with_files("merge_singleton", {
            "one.ds"   => "module A\n    def self.greet\n        return \"hi\"\n    end\nend\n",
            "two.ds"   => "module A\n    module Inner\n        con X = 1\n    end\nend\n",
            "entry.ds" => "use \"./one\"\nuse \"./two\"\necho A.greet\n",
        }) do |entry|
            both_backends(entry, "hi\n")
        end
    end

    # This matches the stage1 import pattern: `class Interpreter` is reopened
    # across five files, with each file importing the previous one.
    #
    # Importing two sibling files that both reopen a class into a third file is not
    # covered here. The interpreter rejects that pattern with
    # `already defined with different superclass`.
    it "merges instance methods when a class is reopened down an import chain" do
        with_files("merge_methods", {
            "one.ds"   => "class C\n    def initialize\n    end\n    def first\n        return 1\n    end\nend\n",
            "two.ds"   => "use \"./one\"\n\nclass C\n    def second\n        return 2\n    end\nend\n",
            "entry.ds" => "use \"./two\"\nc = C.new\necho c.first\necho c.second\n",
        }) do |entry|
            both_backends(entry, "1\n2\n")
        end
    end

    # `param.name_index` is valid only within the chunk that defined the function.
    # Since each file is compiled as its own unit, each unit has its own name pool.
    it "binds named arguments against a signature from another file" do
        with_files("named_across_files", {
            "lib.ds"   => "class Node\n    getter kind: sym\n    def initialize(name: str, kind: sym = :plain)\n        @name = name\n        @kind = kind\n    end\nend\n",
            "entry.ds" => "use \"./lib\"\necho Node.new(\"x\", kind: :special).kind\n",
        }) do |entry|
            both_backends(entry, "special\n")
        end
    end
end

describe "control flow across a block boundary" do
    # Invoking a block re-enters `execute`, but a surrounding `rescue` belongs to
    # the outer execution loop. Handling the rescue in the inner loop resumed the
    # outer frame's bytecode at the wrong instruction.
    it "rescues outside a block an exception raised inside it" do
        source = <<-'DS'
items = [1, 2, 3]
begin
    items.each do |n|
        if n == 2
            raise "boom #{n}"
        end
        echo n
    end
rescue ex
    echo "caught: #{ex.message}"
end
echo "after"
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "1\ncaught: boom 2\nafter\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "1\ncaught: boom 2\nafter\n"
    end

    # A `LoopContext` stores jump addresses for a specific bytecode chunk.
    # Previously, `next` inside a block reused the enclosing `while` context and
    # wrote its jump address into the block's shorter bytecode chunk.
    it "does not let next inside a block reach an enclosing while" do
    # Uses `items` instead of an array literal because a line beginning with `[`
    # is currently parsed as an index expression continuing from the previous line.
        source = <<-'DS'
items = [1, 2, 3]
i = 0
while i < 2
    items.each do |n|
        next if n == 2
        echo n
    end
    i = i + 1
end
echo "done"
DS
        expected = "1\n3\n1\n3\ndone\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq expected
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq expected
    end

    # Returning from inside a `while` bypassed the matching loop-context pop.
    # The stale context then hid the loop that was actually running, causing the
    # next `break` to escape as an unhandled signal.
    it "breaks out of a block after a call that returned from inside a loop" do
        source = <<-'DS'
def scan(limit)
    i = 0
    while i < limit
        return i if i == 2
        i = i + 1
    end
    return -1
end

items = [1, 2, 3, 4]
items.each do |n|
    echo scan(5)
    break if n == 2
end
echo "after"
DS
        expected = "2\n2\nafter\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq expected
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq expected
    end
end

describe "typeof" do
    # The interpreter identifies an instance by its class name. Stage1 dispatches
    # builtins through `typeof(receiver)` checks, so returning `"Instance"` sent
    # every instance through the fallback path.
    it "names an instance by its class on both backends" do
        source = <<-DS
class Token
    def initialize
    end
end
echo typeof(Token.new)
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "Token\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "Token\n"
    end
end

describe "Array#+" do
    it "concatenates on both backends" do
        source = "a = [1, 2]\nb = [3]\necho (a + b)\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "[1, 2, 3]\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "[1, 2, 3]\n"
    end
end

describe "module-level methods" do
    # `self.read_text` could not call `read(path)`: it raised
    # `Undefined variable: read`, while `self.read(path)` worked. Only explicit
    # receiver dispatch consulted the singleton-method table.
    it "lets one def self.x call another by bare name" do
        source = <<-DS
module M
    def self.inner
        return "inner"
    end
    def self.outer
        return inner()
    end
end
echo M.outer
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "inner\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "inner\n"
    end
end

describe "singleton methods on a plain value" do
    it "attaches to one object, not to every equal value" do
    # Singleton methods must be keyed by object identity, not value. Previously,
    # the VM used `hash`, allowing a separate array with identical contents to
    # access the same singleton method.
        source = <<-DS
a = [1, 2]
def a.total
    return 3
end
echo a.total
b = [1, 2]
echo b.total
DS
        [Dragonstone::BackendMode::Native, Dragonstone::BackendMode::Core].each do |backend|
            expect_raises(Exception) do
                Dragonstone.run(source, backend: backend)
            end
        end
    end

    it "refuses a receiver with no identity" do
        source = <<-DS
n = 5
def n.twice
    return 10
end
DS
        [Dragonstone::BackendMode::Native, Dragonstone::BackendMode::Core].each do |backend|
            expect_raises(Exception) do
                Dragonstone.run(source, backend: backend)
            end
        end
    end
end

describe "Map#until" do
    # The interpreter's `call_map_method` returns a `TupleValue` in this case.
    # The VM output `[b, 2]` instead of `{b, 2}`, creating a backend mismatch.
    it "answers a tuple of the matching pair on both backends" do
        source = <<-DS
m = {"a" -> 1, "b" -> 2}
echo m.until do |k, v|
    v == 2
end
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "{b, 2}\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "{b, 2}\n"
    end
end

describe ".class" do
    # `.class` existed for exceptions but could not be called from source because
    # the parser did not accept `class` as a method name after `.`.
    #
    # Changing `expect_method_name` would also allow `def class`, since it is used
    # by both parsing paths. The dot-call path therefore uses its own keyword set.
    it "answers an instance's class on both backends" do
        source = <<-DS
class Foo
    def initialize
    end
end
echo Foo.new.class
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "Foo\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "Foo\n"
    end

    it "still refuses class as a def name" do
        [Dragonstone::BackendMode::Native, Dragonstone::BackendMode::Core].each do |backend|
            expect_raises(Exception) do
                Dragonstone.run("def class\n    return 1\nend\n", backend: backend)
            end
        end
    end

    # `class` is valid as a method name only after `.`. Defining a method named
    # `class` remains invalid, which is why the declaration and dot-call parsing
    # paths stay separate.
    it "still refuses class as a define name inside a class" do
        source = <<-DS
class Foo
    def initialize
    end
    define class
        return "mine"
    end
end
DS
        [Dragonstone::BackendMode::Native, Dragonstone::BackendMode::Core].each do |backend|
            expect_raises(Exception) do
                Dragonstone.run(source, backend: backend)
            end
        end
    end
end

describe "displaying a container" do
    # Classes, structs, and enums are all `ModuleValue`s. Matching `ModuleValue`
    # first in the VM's `display_value` method prevented their more specific
    # display cases from running.
    it "names a class, module and enum the same on both backends" do
        source = <<-DS
module M
    con X = 1
end
enum E
    A
    B
end
class C
    def initialize
    end
end
echo M
echo E
echo E::A
echo C
DS
        expected = "M\nE\nA\nC\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq expected
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq expected
    end
end

describe "fun is non-capturing" do
    # `fun` is a non-capturing function pointer: it can access its parameters and
    # globals, but not the lexical scope where it was defined.
    #
    # Scope lookup walks a single flat stack, so excluding captured locals required
    # the interpreter to establish a lookup floor. Until then, the interpreter and
    # VM disagreed.
    it "cannot see the enclosing method's locals on either backend" do
        source = <<-DS
def outer
    secret = 42
    f = fun(a)
        return a + secret
    end
    return f.call(1)
end
echo outer()
DS
        [Dragonstone::BackendMode::Native, Dragonstone::BackendMode::Core].each do |backend|
            expect_raises(Exception) do
                Dragonstone.run(source, backend: backend)
            end
        end
    end

    it "still sees globals" do
        source = <<-DS
con LIMIT = 10
shared = 5
f = fun(a)
    return a + LIMIT
end
echo f.call(1)
g = fun(a)
    return a + shared
end
echo g.call(1)
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "11\n6\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "11\n6\n"
    end

    # `para` is the capturing callable form. Blocks capture their enclosing scope
    # as well.
    it "does not restrict para or blocks" do
        source = <<-DS
def outer
    secret = 7
    p = ->(a) { a + secret }
    return p.call(1)
end
echo outer()

def blocky
    total = 0
    items = [1, 2, 3]
    items.each do |n|
        total = total + n
    end
    return total
end
echo blocky()
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "8\n6\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "8\n6\n"
    end
end

describe "object_id" do
    # Singleton methods are attached by object identity, ensuring that
    # `def a.shout` belongs to `a` alone rather than to every equal object.
    it "distinguishes equal values and matches aliases" do
        source = <<-DS
a = [1, 2]
b = [1, 2]
c = a
echo a.object_id == b.object_id
echo a.object_id == c.object_id
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "false\ntrue\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "false\ntrue\n"
    end

    it "answers nil for values with no identity" do
        source = <<-DS
echo 5.object_id.nil?
echo true.object_id.nil?
echo :sym.object_id.nil?
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "true\ntrue\ntrue\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "true\ntrue\ntrue\n"
    end
end

describe "a line opening with [" do
    # A postfix `[` is an index expression only when it appears on the same line
    # as the preceding expression. On a new line, it begins an array literal.
    #
    # Without this distinction, `x = 5` followed by `[1, 2, 3].each` was parsed as
    # `5[1, 2, 3]`, producing `Expected RBRACKET, got COMMA`.
    it "starts a new statement rather than indexing the line above" do
        source = <<-DS
x = 5
[1, 2, 3].each do |n|
    echo n
end
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "1\n2\n3\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "1\n2\n3\n"
    end

    it "still indexes on the same line" do
        source = <<-DS
a = [10, 20, 30]
echo a[1]
nested = [[1, 2], [3, 4]]
echo nested[1][0]
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq "20\n3\n"
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq "20\n3\n"
    end
end

describe "e! rendering" do
    # Several AST nodes did not implement `to_source(io)`. As a result, `e!` on an
    # array literal raised `Not Implemented` in stage0, even though stage1 rendered
    # the same expression successfully.
    it "renders array, conditional and bag expressions on both backends" do
        source = <<-DS
nums = [1, 2, 3]
e! nums
e! [4, 5]
flag = true
e! flag ? "yes" : "no"
b = bag(str).new
b.add("x")
e! b
DS
        expected = <<-OUT
nums # -> [1, 2, 3]
[4, 5] # -> [4, 5]
flag ? "yes" : "no" # -> "yes"
b # -> ["x"]

OUT
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq expected
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq expected
    end
end
