require "spec"
require "../src/dragonstone/shared/parser/parser"
require "../src/dragonstone/shared/resolver/resolver"

describe Dragonstone::ModuleResolver do
    it "returns absolute remote specs as-is" do
        config = Dragonstone::ModuleConfig.new([Dir.current])
        resolver = Dragonstone::ModuleResolver.new(config)
        item = Dragonstone::AST::UseItem.new(
            kind: Dragonstone::AST::UseItemKind::Paths,
            specs: ["https://example.com/examples/unicode.ds"]
        )

        resolver.expand_use_item(item, Dir.current).should eq([
            "https://example.com/examples/unicode.ds"
        ])
    end

    it "resolves relative specs against remote parents" do
        config = Dragonstone::ModuleConfig.new([Dir.current])
        resolver = Dragonstone::ModuleResolver.new(config)
        base_dir = resolver.base_directory("https://cdn.example.com/examples/use.ds")
        item = Dragonstone::AST::UseItem.new(
            kind: Dragonstone::AST::UseItemKind::Paths,
            specs: ["./unicode"]
        )

        resolver.expand_use_item(item, base_dir).should eq([
            "https://cdn.example.com/examples/unicode.ds"
        ])
    end
end
