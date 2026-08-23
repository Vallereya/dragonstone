require "spec"
require "../src/dragonstone"

# `f(1, b: 2)` previously encoded `b: 2` as an inline `NamedTuple` and passed
# it positionally. As a result, the parameter `b` received `{b: 2}` instead of
# `2`, with no error raised.
#
# Named arguments now use a dedicated AST node and are matched to parameters by
# name.
#
# This test applies only to the interpreter. The VM does not support named
# arguments yet and rejects programs that use them during compilation, so
# running this case through `both_backends` would not be meaningful.
describe "named arguments" do
    describe "binding" do
        it "binds a trailing named argument to its parameter" do
            source = "def f(a, b)\n  echo \"a=\#{a} b=\#{b}\"\nend\nf(1, b: 2)\n"
            Dragonstone.run(source).output.should eq("a=1 b=2\n")
        end

        it "binds when every argument is named" do
            source = "def f(a, b)\n  echo \"a=\#{a} b=\#{b}\"\nend\nf(a: 1, b: 2)\n"
            Dragonstone.run(source).output.should eq("a=1 b=2\n")
        end

        it "binds out of order" do
            source = "def f(a, b)\n  echo \"a=\#{a} b=\#{b}\"\nend\nf(b: 2, a: 1)\n"
            Dragonstone.run(source).output.should eq("a=1 b=2\n")
        end

        it "lets a positional argument fill the slot a named one skipped" do
            source = "def f(a, b)\n  echo \"a=\#{a} b=\#{b}\"\nend\nf(b: 2, 1)\n"
            Dragonstone.run(source).output.should eq("a=1 b=2\n")
        end
    end

    describe "with defaults" do
        it "skips over a defaulted parameter" do
            # A named argument can skip an earlier parameter without changing that
            # parameter’s default value. Previously, defaults were appended by position,
            # which caused `b` to receive the default intended for `c`.
            source = "def g(a, b = 99, c = 100)\n  echo \"a=\#{a} b=\#{b} c=\#{c}\"\nend\ng(1, c: 5)\n"
            Dragonstone.run(source).output.should eq("a=1 b=99 c=5\n")
        end

        it "still applies all defaults when nothing is named" do
            source = "def g(a, b = 99, c = 100)\n  echo \"a=\#{a} b=\#{b} c=\#{c}\"\nend\ng(1)\ng(1, 2)\n"
            Dragonstone.run(source).output.should eq("a=1 b=99 c=100\na=1 b=2 c=100\n")
        end
    end

    describe "receivers" do
        it "binds on a module method" do
            source = <<-'DS'
            module M
                extend self
                def greet(name, greeting = "Hello")
                    echo "#{greeting}, #{name}!"
                end
            end
            M.greet("Ada")
            M.greet("Ada", greeting: "Hi")
            M.greet(greeting: "Yo", name: "Ada")
            DS
            Dragonstone.run(source + "\n").output.should eq("Hello, Ada!\nHi, Ada!\nYo, Ada!\n")
        end

        it "binds on a constructor, including out of order" do
            source = <<-DS
            class Box
                def initialize(w, h = 2)
                    @w = w
                    @h = h
                end
                def area
                    return @w * @h
                end
            end
            echo Box.new(3).area
            echo Box.new(3, h: 4).area
            echo Box.new(h: 4, w: 3).area
            DS
            Dragonstone.run(source + "\n").output.should eq("6\n12\n12\n")
        end

        # Struct fields are initialized through named arguments rather than an explicit
        # `initialize` method. Previously, those arguments were passed as a single
        # `NamedTuple` instead of being bound to their individual fields.
        it "still constructs a struct from named fields" do
            source = <<-DS
            struct Point
                property x: int
                property y: int
            end
            p = Point.new(x: 1, y: 2)
            echo p.x
            echo p.y
            DS
            Dragonstone.run(source + "\n").output.should eq("1\n2\n")
        end
    end

    describe "errors" do
        it "rejects an unknown parameter name" do
            expect_raises(Dragonstone::TypeError, /has no parameter named 'zzz'/) do
                Dragonstone.run("def f(a, b)\n  echo a\nend\nf(1, zzz: 2)\n")
            end
        end

        it "rejects two values for the same parameter" do
            expect_raises(Dragonstone::TypeError, /two values for parameter 'a'/) do
                Dragonstone.run("def f(a, b)\n  echo a\nend\nf(a: 1, a: 2, b: 3)\n")
            end
        end

        it "rejects a named argument aimed at a builtin" do
            expect_raises(Exception) do
                Dragonstone.run("echo [1, 2].includes?(value: 1)\n")
            end
        end
    end

    # A braced named tuple remains a regular positional argument. Only the
    # unbraced form is interpreted as a named argument.
    it "leaves a braced named tuple as a single value" do
        source = "def f(a)\n  echo a\nend\nf({x: 1, y: 2})\n"
        Dragonstone.run(source).output.should eq("{x: 1, y: 2}\n")
    end

    # For calls to top-level functions, `DefaultArguments` resolves named arguments
    # into positional order during lowering. The VM therefore never receives a
    # `NamedArgument` node and can execute the call normally.
    it "runs on the core backend when the callee is a top-level function" do
        result = Dragonstone.run(
            "def f(a, b)\n  echo b\nend\nf(1, b: 2)\n",
            backend: Dragonstone::BackendMode::Core
        )
        result.output.should eq("2\n")
    end

    # Calls with a receiver cannot be resolved statically because the transform
    # only knows about plain functions. A `NamedArgument` therefore reaches the VM,
    # where `INVOKE_NAMED` matches it to the callee’s parameters at runtime.
    it "binds a receiver call's named arguments on the core backend" do
        result = Dragonstone.run(
            "module M\n  extend self\n  def greet(a, b)\n    echo b\n  end\nend\nM.greet(1, b: 2)\n",
            backend: Dragonstone::BackendMode::Core
        )
        result.output.should eq("2\n")
    end

    it "binds out of order on the core backend too" do
        result = Dragonstone.run(
            "module M\n  extend self\n  def greet(a, b)\n    echo a\n  end\nend\nM.greet(b: 2, a: 1)\n",
            backend: Dragonstone::BackendMode::Core
        )
        result.output.should eq("1\n")
    end

    # Default arguments on methods were not previously expanded for the VM. Because
    # lowering cannot resolve calls through a receiver, those calls reached the VM
    # with too few arguments and failed an arity check.
    #
    # Method signatures now store each default value as a separately compiled
    # chunk, allowing the VM to apply defaults at runtime.
    it "fills a method's default parameters on the core backend" do
        result = Dragonstone.run(
            "module M\n  extend self\n  def greet(name, greeting = \"Hello\")\n    echo greeting\n  end\nend\nM.greet(\"Ada\")\n",
            backend: Dragonstone::BackendMode::Core
        )
        result.output.should eq("Hello\n")
    end

    # Named arguments can skip a parameter that has a default. For example:
    #
    #   f(1, c: 7)
    #
    # against:
    #
    #   f(a, b = 2, c = 3)
    #
    # supplies `a` and `c`, while `b` should retain its default value of `2`.
    # Previously, both backends rejected this call as if `b` were required.
    #
    # Plain function calls did not reveal the bug because `DefaultArguments`
    # expands their defaults in the AST. Calls with receivers are intentionally
    # excluded from that transform, so `f(1, c: 7)` worked while
    # `T.new(1, c: 7)` and `M.f(1, c: 7)` failed.
    #
    # This made constructors that pass named arguments after a defaulted parameter
    # unusable, including many AST node constructors in `bootstrap/`.
    describe "a named argument skipping a defaulted parameter" do
        source_fn = "def f(a, b = 2, c = 3)\n  echo \"\#{a}/\#{b}/\#{c}\"\nend\nf(1, c: 7)\n"

        source_ctor = <<-'DS'
        class T
            def initialize(a, b = 2, c = 3)
                @a = a
                @b = b
                @c = c
            end
            def show
                echo "#{@a}/#{@b}/#{@c}"
            end
        end
        T.new(1, c: 7).show
        DS

        it "fills the hole from the default on a bare call" do
            Dragonstone.run(source_fn).output.should eq("1/2/7\n")
        end

        it "fills the hole from the default on a constructor" do
            Dragonstone.run(source_ctor).output.should eq("1/2/7\n")
        end

        it "fills the hole from the default on a constructor, core backend" do
            Dragonstone.run(source_ctor, backend: Dragonstone::BackendMode::Core)
                .output.should eq("1/2/7\n")
        end

        # Skipping a parameter is still an error when that parameter has no default
        # value. In that case, the call has a genuine missing argument rather than a
        # valid gap filled by a default.
        it "still rejects a hole with no default behind it" do
            source = "def f(a, b, c = 3)\n  echo b\nend\nf(1, c: 7)\n"
            expect_raises(Dragonstone::TypeError, /missing a value for parameter 'b'/) do
                Dragonstone.run(source)
            end
        end
    end
end
