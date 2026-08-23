require "spec"
require "../src/dragonstone"

private def both_backends(source : String, expected : String)
    Dragonstone.run(source).output.should eq(expected)
    Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq(expected)
end

# These are two separate bugs discovered while porting `bindings.ds`.
#
# Its `rewrite_node_array` method contains a `begin ... ensure ... end` block
# where the main body can raise an exception and the `ensure` block always calls
# `scopes.pop`. The exception is handled by the calling method.
#
# That control-flow pattern exposed both problems:
#
# - The VM could hang while handling the exception.
# - Without a `rescue` clause, bytecode generation could fail during compilation.
describe "ensure" do
    # When an exception occurs, the VM jumps directly to `ensure_ip`. This skips
    # the `POP_HANDLER` instruction that normally removes the handler from the
    # stack.
    #
    # Because the handler remained on the stack, `CHECK_RETHROW` raised the
    # exception again, and `handle_exception` selected the same topmost handler.
    # The VM then re-entered the same `ensure` block repeatedly, creating an
    # infinite loop and running the `ensure` body on every iteration.
    #
    # The interpreter has always unwound this case correctly, so the issue only
    # appeared when running with `--backend core`. Bootstrap specifications run
    # stage 1 with that backend, which is why the regression was visible there.
    describe "a raise crossing a method's ensure on the way to a caller's rescue" do
        source = <<-'DS'
        define risky
            begin
                raise "boom"
            ensure
                echo "ensure ran"
            end
        end

        begin
            risky()
        rescue e
            echo "caught"
        end
        DS

        it "runs the ensure exactly once and reaches the caller's rescue" do
            both_backends(source, "ensure ran\ncaught\n")
        end
    end

    # `compile_raise` always reset `@stack_depth` to `0`, which is only correct
    # when compiling at the top level.
    #
    # A `begin ... ensure ... end` expression compiles its body with
    # `preserve_last: true`, meaning the bytecode generator expects the body to
    # leave one value on the stack. After `compile_raise` reset the tracked stack
    # depth to zero, the generator incorrectly believed no value remained.
    #
    # The `ensure` block then emitted its own `POP` instructions, causing the
    # generator's stack-depth counter to become negative and raising a
    # `Bytecode stack underflow` error during compilation.
    #
    # A `rescue` clause happened to increase the tracked stack depth again, hiding
    # the issue. As a result, only the `ensure` form without a `rescue` clause
    # failed.
    describe "a begin/ensure with no rescue whose body raises" do
        # This regression test verifies that the program compiles successfully.
        # Previously, bytecode generation failed with a `Bytecode stack underflow`
        # error before the VM could run.
        #
        # The expected result is the program's own `x` error, not a compiler error.
        it "compiles, and propagates the program's own exception" do
            source = "begin\n    echo \"body\"\n    raise \"x\"\nensure\n    echo \"e\"\nend\n"

            [nil, Dragonstone::BackendMode::Core].each do |backend|
                error = expect_raises(Exception) do
                    backend ? Dragonstone.run(source, backend: backend) : Dragonstone.run(source)
                end
                error.message.not_nil!.should contain("x")
                error.message.not_nil!.should_not contain("underflow")
            end
        end

        # This uses the same control-flow pattern, but catches the exception so the
        # `ensure` block's output can be checked. The `ensure` block must run exactly
        # once while the exception is unwound.
        it "runs the ensure on the way out" do
            both_backends(
                "begin\n    begin\n        echo \"body\"\n        raise \"x\"\n    ensure\n        echo \"e\"\n    end\nrescue err\n    echo \"caught\"\nend\n",
                "body\ne\ncaught\n"
            )
        end

        it "still works with a rescue present" do
            both_backends(
                "begin\n    raise \"x\"\nrescue e\n    echo \"c\"\nensure\n    echo \"e\"\nend\n",
                "c\ne\n"
            )
        end
    end

    it "runs an ensure with no exception at all" do
        both_backends("begin\n    echo \"b\"\nensure\n    echo \"e\"\nend\n", "b\ne\n")
    end

    # Exception-handler re-entry guard:
    #
    # `handle_exception` keeps a handler on the stack while its `rescue` body runs.
    # The handler must remain available because:
    #
    # - `retry` needs the handler's `body_ip` to restart the protected code.
    # - The handler's associated `ensure` block may still need to run afterward.
    #
    # The bug was that, although the handler needed to stay on the stack, it also
    # remained eligible to catch exceptions. If an exception was raised inside its
    # own `rescue` body, the runtime found that same handler first and jumped back
    # into the same `rescue` body indefinitely.
    #
    # The fix keeps the handler on the stack but temporarily marks it as ineligible
    # while its `rescue` body is executing. This is implemented with a parallel
    # `@handling : Array(Bool)` alongside `@handlers`, instead of removing the
    # handler when it is entered.
    #
    # Removing the handler on entry appears to fix the first scenario below, but
    # silently breaks the final two scenarios. They are grouped here to protect
    # against that incomplete solution.
    #
    # `handler_guard.sh` contains the same three scenarios as a permanent 
    # regression check. It was written before this fix and treated
    # `ensure_reraise` as a known expected failure until the fix was added.
    describe "a raise inside its own rescue body (gap 1p)" do
        # This is the original bug: it caused an infinite loop in the core backend,
        # while the native backend handled it correctly.
        #
        # NOTE: The exception is intentionally not included in the output. The core and
        # native backends currently format raised string exceptions differently:
        #
        # - Native: `InterpreterError: y`
        # - Core: `y`
        #
        # That difference is an unrelated, pre-existing diagnostics issue: an
        # unwrapped `raise` in the VM loses the exception class. Including `e` here would
        # cause this test to fail because of that formatting difference, making it appear
        # to be a regression in this behavior when it is not.
        it "propagates outward instead of re-entering the same handler" do
            both_backends(<<-'DS', "outer caught\nafter\n")
            begin
                begin
                    raise "x"
                rescue
                    raise "y"
                end
            rescue e
                echo "outer caught"
            end
            echo "after"
            DS
        end

        # When an exception unwinds past this handler, its associated `ensure` block must
        # still run exactly once before an outer `rescue` block handles the exception.
        #
        # This protects against implementations that remove the handler too early when
        # entering it, which can silently skip its `ensure` block.
        it "runs the same handler's ensure on the way out, then reaches the outer rescue" do
            both_backends(<<-'DS', "inner rescued\nensure ran\nouter caught\ndone\n")
            begin
                begin
                    raise "boom"
                rescue ex
                    echo "inner rescued"
                    raise ex
                ensure
                    echo "ensure ran"
                end
            rescue outer
                echo "outer caught"
            end
            echo "done"
            DS
        end

        # `retry` restarts the protected body, so its exception handler must become
        # available again. If the handler is not reset, an exception raised during the
        # second attempt skips the handler that performed the retry.
        it "makes the handler eligible again after retry" do
            both_backends(<<-'DS', "gave up after 3\nafter\n")
            n = 0
            begin
                n = n + 1
                raise "always"
            rescue e
                if n < 3
                    retry
                end
                echo "gave up after #{n}"
            end
            echo "after"
            DS
        end

        # This test raises an exception from a `rescue` block while calling another block.
        # The inner handler was created by a nested `execute` call, so propagating the
        # exception past it crosses an interpreter boundary.
        #
        # This path is tested because the fix makes it reachable for the first time.
        # Previously, the exception incorrectly re-entered the inner handler instead of
        # continuing to unwind to the next applicable handler.
        it "unwinds out of a block when the rescue body inside it raises" do
            both_backends(<<-'DS', "outer caught\nafter\n")
            begin
                [1].each do |n|
                    begin
                        raise "a"
                    rescue
                        raise "b"
                    end
                end
            rescue e
                echo "outer caught"
            end
            echo "after"
            DS
        end

        # A new `begin` block created inside a `rescue` block can still handle exceptions
        # raised within it. Exception-handling state belongs to each individual handler,
        # rather than using a global “currently rescuing” flag.
        it "still catches inside a nested begin opened within a rescue body" do
            both_backends(<<-'DS', "inner handled\nouter body continued\nafter\n")
            begin
                raise 1
            rescue
                begin
                    raise 2
                rescue
                    echo "inner handled"
                end
                echo "outer body continued"
            end
            echo "after"
            DS
        end
    end

    # When execution enters the `ensure` block, this handler is marked as no longer usable.
    # If another exception is raised afterward, it must be handled by the next available
    # handler rather than reusing the one that already handled the first exception.
    it "unwinds through two nested ensures in order" do
        both_backends(<<-'DS', "inner\nouter\ncaught\n")
        define inner
            begin
                raise "boom"
            ensure
                echo "inner"
            end
        end

        define outer
            begin
                inner()
            ensure
                echo "outer"
            end
        end

        begin
            outer()
        rescue e
            echo "caught"
        end
        DS
    end
end
