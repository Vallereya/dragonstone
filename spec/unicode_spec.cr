require "spec"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/resolver/encoding"

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
