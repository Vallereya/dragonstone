require "spec"
require "../src/dragonstone"

private def both_backends(source : String, expected : String)
    Dragonstone.run(source).output.should eq(expected)
    Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq(expected)
end

# Two coupled defects in the VM's block model. They had to be fixed together:
# closing the first makes the second fire far more often, which is why an
# earlier attempt at the first alone regressed two previously-identical samples.
#
# The model: a block body *shares* its owner's locals array by reference. That
# is how it sees enclosing variables at all, there is no scope chain, just one
# flat indexed array per frame.
#
#   (a) The shared array came from `current_frame`, meaning whoever *called* the
#       block. For a builtin (`xs.each { }`) the caller is the creator, so it
#       worked. For `yield` it is the method doing the yielding, so the block
#       got that method's locals and every enclosing name came back
#       `Undefined variable`. `checker.ds:56`,
#       `with_name(node.name) { node.body.each { ... } }`, is exactly that
#       shape, so stage1's type checker failed on **any class definition** under
#       `--backend core`, which is what every bootstrap spec runs stage1 on.
#
#   (b) Because the array is shared, a block's *parameters* were written into
#       the owner's slots and stayed there. `x = "OUTER"` then
#       `[1, 2].each do |x|` left `x == 2` behind.
#
# Fix: block frames take their locals from the frame that *wrote* the block
# (tracked already as `BlockValue#owner_frame_id`, previously used only for
# non-local return), and parameter slots are saved on entry and restored on
# every frame exit: normal, non-local return, and exception unwinding.
describe "block scoping" do
    describe "a yielded block sees the creator's locals" do
        it "resolves an enclosing local through a user-defined yield" do
            both_backends(<<-'DS', "sees: VALUE\n")
            define wrapper(label)
                yield
            end
            define outer(node)
                wrapper("x") { echo "sees: #{node}" }
                return nil
            end
            outer("VALUE")
            DS
        end

        it "resolves one through a yield that passes arguments" do
            both_backends(<<-'DS', "n=OUTER y=42\n")
            define wrapper(label)
                yield 42
            end
            define outer(node)
                wrapper("x") { |y| echo "n=#{node} y=#{y}" }
                return nil
            end
            outer("OUTER")
            DS
        end

        # Built-in lookup already works. This test ensures that future changes to
        # owner lookup do not break it unnoticed.
        it "still resolves one through a builtin iteration" do
            both_backends(<<-'DS', "sees: V\n")
            define outer(node)
                [1].each { |x| echo "sees: #{node}" }
                return nil
            end
            outer("V")
            DS
        end

        # This exercises two nested block frames, both invoked with `yield`. To find
        # its defining scope, the inner block must skip over the intervening `wrapper`
        # call frames. `block_locals_source` performs that frame traversal.
        #
        # This does not test `yield` inside a block body to invoke the enclosing
        # method's block. Neither backend supports that case yet: both report
        # `No block given`. Since this is a shared limitation rather than a behavioral
        # difference, it is outside the scope of this test.
        it "resolves through two nested yielded blocks" do
            both_backends(<<-'DS', "deep: V\n")
            define wrapper(l)
                yield
            end
            define outer(node)
                wrapper("a") do
                    wrapper("b") do
                        echo "deep: #{node}"
                    end
                end
                return nil
            end
            outer("V")
            DS
        end
    end

    describe "block parameters shadow rather than overwrite" do
        it "leaves an enclosing local of the same name alone" do
            both_backends(<<-'DS', "in: 1\nin: 2\nafter: OUTER\n")
            define run_it
                x = "OUTER"
                [1, 2].each do |x|
                    echo "in: #{x}"
                end
                echo "after: #{x}"
                return nil
            end
            run_it()
            DS
        end

        it "leaves it alone when the block is reached by yield" do
            both_backends(<<-'DS', "in: 7\nafter: OUTER\n")
            define wrapper(l)
                yield 7
            end
            define run_it
                x = "OUTER"
                wrapper("w") { |x| echo "in: #{x}" }
                echo "after: #{x}"
                return nil
            end
            run_it()
            DS
        end

        # Variables are restored whenever a frame exits. This test ensures that if a
        # block raises an exception, its parameter does not remain in the owner’s
        # variable scope.
        it "restores the slot when the block raises" do
            both_backends(<<-'DS', "caught\nafter: OUTER\n")
            define run_it
                x = "OUTER"
                begin
                    [1].each do |x|
                        raise "boom"
                    end
                rescue e
                    echo "caught"
                end
                echo "after: #{x}"
                return nil
            end
            run_it()
            DS
        end

        # Assignments to enclosing variables that are not block parameters must still
        # update the outer scope. That behavior is what gives blocks closure semantics,
        # and parameter shadowing must not prevent it.
        it "still writes through to an enclosing local" do
            both_backends(<<-'DS', "after: 6\n")
            define run_it
                total = 0
                [1, 2, 3].each do |n|
                    total += n
                end
                echo "after: #{total}"
                return nil
            end
            run_it()
            DS
        end
    end

# Recursion exposed a gap in this spec and allowed a real bug to go unnoticed.
#
# Earlier cases place a method on the call stack only once. During recursion,
# however, several frames of the same method are active at the same time.
# Resolving a block's owner must therefore identify the specific frame that
# created the block, not merely any frame currently executing that method.
#
# This was not previously covered. In the stage1 interpreter, recursive calls
# did not receive separate frames, so every recursion level shared the same
# bindings. The innermost assignment overwrote the others, causing `rec(3)` to
# return `0` instead of `6`.
#
# The spec covers two forms because they isolate different failure modes:
#
# - `plain` uses no blocks, isolating recursive frame identity from closure
#   behavior.
# - `carrying` passes a block created at each recursion level and closed over
#   that level's local variable. It verifies that lookup resolves to the
#   block's creating frame rather than the innermost active frame.
    describe "recursion" do
        # This case uses no blocks. If it fails, recursive call frames are not isolated;
        # the problem is unrelated to block or closure behavior.
        it "gives each recursive call its own locals" do
            both_backends(<<-'DS', "6\n")
            define rec(n)
                local = n
                if n <= 0
                    return 0
                end
                inner = rec(n - 1)
                return local + inner
            end
            echo rec(3)
            DS
        end

        # Each recursive call creates its own block. While `walk(2)` is running, the
        # block passed to it was created by `walk(3)`, so it must read `mine` from the
        # `walk(3)` frame—not from the innermost active frame.
        #
        # The expected result, `506`, is calculated from the call structure:
        #
        #   walk(3): mine = 300, block result = 3
        #   walk(2): mine = 200, block result = 300 + 2 = 302
        #   walk(1): mine = 100, block result = 200 + 1 = 201
        #   walk(0): returns 0
        #
        #   => 201, then 302 + 201 = 503, then 3 + 503 = 506
        #
        # Resolving the block against the innermost active frame produces `303`
        # instead. The test asserts the exact value because this bug returns an
        # incorrect result rather than raising an error.
        it "resolves a block's locals to its creating frame, not the innermost" do
            both_backends(<<-'DS', "506\n")
            define walk(n)
                mine = n * 100
                if n <= 0
                    return 0
                end
                got = yield n
                deeper = walk(n - 1) do |x|
                    mine + x
                end
                return got + deeper
            end
            echo walk(3) do |x|
                x
            end
            DS
        end
    end
end
