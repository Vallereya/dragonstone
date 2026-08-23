require "spec"
require "../src/dragonstone"

# `Dragonstone.run` executes inline source code, while `Dragonstone.run_file`
# is the path used by the CLI. They are intended to be two entry points into the
# same execution pipeline.
#
# The difference went unnoticed because all 424 specification examples used the 
# inline path, while normal CLI use always went through the file-based path.
#
# Before the pipelines were unified, the differences caused several problems:
#
# - `run` created a basic `Interpreter` for the native backend. As a result,
#   local variables in recursive methods were shared between calls instead of
#   being stored per stack frame. For example, `rec(3)` returned `0` through
#   the inline path but `6` through the CLI.
# - `run` did not resolve imports, so `use` statements in inline source failed
#   to load their targets.
# - `caesar_cipher.ds` hung when executed through one path but not the other.
#
# `door_sweep.sh` checks the full corpus for differences between
# the two entry points and is the primary cross-path validation tool. These
# focused cases also remain in the test suite so regressions fail during normal
# test runs; a standalone sweep only catches problems when someone remembers to
# run it.
private def door_root : String
    root = File.join(Dir.current, ".cache", "door_parity")
    Dir.mkdir_p(root)
    root
end

# Writes `source` to a temporary file, then runs it through both execution paths
# and verifies that they produce the same result.
#
# `source_name` is passed to the inline execution path so that both paths resolve
# relative imports from the same directory.
private def both_doors(name : String, source : String) : String
    path = File.join(door_root, name)
    File.write(path, source)

    inline = Dragonstone.run(source, source_name: path).output
    viafile = Dragonstone.run_file(path).output

    inline.should eq(viafile)
    inline
end

describe "door parity" do
    # This was the original test case that revealed the problem.
    #
    # A recursive method that keeps a local variable exposed a behavioral difference
    # between the two execution pipelines. This file exists to preserve that
    # regression case.
    it "agrees on a recursive method holding a local" do
        both_doors("rec.ds", <<-DS).should eq("6\n")
        def rec(n)
            total = 0
            if n <= 0
                return 0
            end
            total = n + rec(n - 1)
            return total
        end
        echo rec(3)
        DS
    end

    # Cause 2: The inline execution path registered its entry node but did not
    # resolve imports, so imported names were unavailable.
    #
    # This could not be fixed only by adding import resolution at that point,
    # because the two execution paths also processed work in a different order.
    # The `run` path analyzed and lowered an AST that had been created before any
    # imports could be resolved.
    it "agrees on a program that imports another file" do
        File.write(File.join(door_root, "greeter.ds"), <<-DS)
        module Greeter
            def self.hello
                return "hi"
            end
        end
        DS

        both_doors("importer.ds", <<-DS).should eq("hi\n")
        use "./greeter"
        echo Greeter.hello()
        DS
    end

    # A method call must not be able to access local variables from its caller.
    #
    # This test covers both control-flow paths and expects an error in each case.
    # Previously, the interpreter silently allowed caller-local variables to leak
    # into the called method.
    it "agrees that a callee cannot see its caller's locals" do
        path = File.join(door_root, "leak.ds")
        source = <<-DS
        def inner
            echo secret
        end

        def outer
            secret = 42
            inner()
        end

        outer()
        DS
        File.write(path, source)

        expect_raises(Dragonstone::NameError, /secret/) { Dragonstone.run(source, source_name: path) }
        expect_raises(Dragonstone::NameError, /secret/) { Dragonstone.run_file(path) }
    end

    it "agrees on a struct built from named fields" do
        both_doors("struct.ds", <<-DS).should eq("1\n2\n")
        struct Point
            property x: int
            property y: int
        end
        p = Point.new(x: 1, y: 2)
        echo p.x
        echo p.y
        DS
    end

    # This issue was deferred for several weeks because it appeared to be caused by
    # either a `con-in-class` problem or a character-versus-string mismatch.
    #
    # The actual cause was neither: a loop variable was overwritten across stack
    # frames, preventing the loop from terminating. The loop also exited through
    # only one of its two possible control-flow paths.
    #
    # A timeout is the clearest indication of this regression, so this test runs
    # the original corpus file directly instead of using a smaller reduced example.
    it "agrees on caesar_cipher, and terminates through both doors" do
        path = File.join(Dir.current, "examples", "rosetta", "caesar_cipher.ds")
        pending! "corpus file missing" unless File.file?(path)

        inline = Dragonstone.run(File.read(path), source_name: path).output
        viafile = Dragonstone.run_file(path).output

        inline.should eq(viafile)
        inline.should contain("THEQUICKBROWNFOXJUMPSOVERTHELAZYDOG")
    end
end
