require "spec"
require "../src/dragonstone"

private def both_backends(source : String, expected : String)
    Dragonstone.run(source).output.should eq(expected)
    Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq(expected)
end

# `let` and `fix` bindings are implemented by renaming the declared variable
# and updating every reference to it. For example:
#
#   let a = 1
#
# becomes:
#
#   __ds_let_1_a = 1
#
# Interpolated strings store their embedded expressions as source text, so
# each expression must be parsed again, rewritten with the mangled name, and
# converted back to source. Otherwise, the interpolation still refers to the
# original variable name, which no longer exists.
#
# This rewrite was never applied because `LexicalBindings` checked for an
# `:expression` token, but the lexer emits `:interpolation` tokens. The
# `:expression` tag is only introduced later by `normalized_parts`, making the
# original branch unreachable.
#
# As a result, `let` and `fix` bindings were unavailable inside interpolated
# strings on both backends:
#
#   let a = 1
#   echo "v=#{a}" # => Undefined variable: a
#
# Checking for `:string` fixes this reliably because `:string` is the token
# type produced directly by the lexer.
describe "let/fix bindings inside string interpolation" do
    it "resolves a let binding" do
        both_backends("let a = 1\necho \"v=\#{a}\"\n", "v=1\n")
    end

    it "resolves a fix binding" do
        both_backends("fix b = 2\necho \"v=\#{b}\"\n", "v=2\n")
    end

    it "resolves one inside an assignment's value" do
        both_backends("let a = 1\nx = \"v=\#{a}\"\necho x\n", "v=1\n")
    end

    it "resolves one nested in a block" do
        both_backends("let a = 1\nif a == 1\n    echo \"yes \#{a}\"\nend\n", "yes 1\n")
    end

    it "resolves several in one string, with literal text between" do
        both_backends("let a = 1\nfix b = 2\necho \"\#{a} and \#{b}!\"\n", "1 and 2!\n")
    end

    it "leaves an ordinary local alone" do
        both_backends("a = 1\necho \"v=\#{a}\"\n", "v=1\n")
    end

    # A parameter with the same name takes precedence over the outer binding.
    # The interpolation must resolve to the parameter, not the mangled outer variable.
    it "honours shadowing by a parameter" do
        both_backends(
            "let a = 1\ndef show(a)\n    echo \"p=\#{a}\"\nend\nshow(9)\n",
            "p=9\n"
        )
    end
end
