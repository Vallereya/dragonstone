require "spec"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/resolver/encoding"
require "../src/dragonstone/shared/runtime/ffi/ffi"

describe "Dragonstone Unicode support" do
    it "reads UTF-8 sources that include emoji identifiers" do
        File.tempfile("dragonstone-unicode", suffix: ".ds") do |file|
            file.print("🔥 = \"fire\"\necho 🔥\n")
            file.flush

            source = Dragonstone::Encoding.read(file.path)
            source.data.should contain("🔥")

            lexer = Dragonstone::Lexer.new(source.data, file.path)
            tokens = lexer.tokenize

            tokens.count { |token| token.type == :IDENTIFIER && token.value == "🔥" }.should eq(2)
        end
    end

    it "expands unicode escape sequences inside string literals" do
        lexer = Dragonstone::Lexer.new(%(message = "\\u{1F525}"), "<memory>")
        tokens = lexer.tokenize
        string_token = tokens.find { |token| token.type == :STRING }
        string_token.not_nil!.value.should eq("🔥")
    end

    it "normalizes Unicode strings and checks canonical equivalence" do
        composed = "é"
        decomposed = "e\u{0301}"

        normalized = Dragonstone::FFI.call_crystal("unicode_normalize", [composed, "NFD"])
        normalized.should eq(decomposed)

        canonical = Dragonstone::FFI.call_crystal("unicode_canonical_equivalent", [composed, decomposed])
        canonical.should eq(true)
    end

    it "applies Unicode case mapping and folding" do
        upcased = Dragonstone::FFI.call_crystal("unicode_upcase", ["straße"])
        upcased.should eq("STRASSE")

        folded = Dragonstone::FFI.call_crystal("unicode_casefold", ["ß"])
        folded.should eq("ss")
    end

    it "segments Unicode grapheme clusters" do
        count = Dragonstone::FFI.call_crystal("unicode_grapheme_count", ["👨‍👩‍👧‍👦"])
        count.should eq(1)
    end

    it "returns general category and combining class" do
        category = Dragonstone::FFI.call_crystal("unicode_general_category", [65])
        category.should eq("Lu")

        combining = Dragonstone::FFI.call_crystal("unicode_combining_class", [769])
        combining.should eq(230)
    end

    it "compares strings with casefold collation" do
        comparison = Dragonstone::FFI.call_crystal("unicode_compare", ["straße", "STRASSE", "CASEFOLD"])
        comparison.should eq(0)
    end

    it "rejects invalid UTF-8 byte sequences before lexing" do
        File.tempfile("dragonstone-invalid", suffix: ".ds") do |file|
            file.close
            File.open(file.path, "wb") do |io|
                io.write_byte(0xFF_u8)
            end

            expect_raises(Dragonstone::SyntaxError) do
                Dragonstone::Encoding.read(file.path)
            end
        end
    end
end
