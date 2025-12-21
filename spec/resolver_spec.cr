require "spec"
require "file_utils"
require "../src/dragonstone/shared/language/parser/parser"
require "../src/dragonstone/shared/language/resolver/resolver"

private def with_tmpdir(&block : String ->)
    dir = File.join(Dir.current, "tmp_resolver_#{Process.pid}_#{Random.new.rand(1_000_000)}")
    Dir.mkdir_p(dir)
    begin
        yield dir
    ensure
        FileUtils.rm_rf(dir)
    end
end

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

    it "skips resolving imports to the current file when excluded" do
        with_tmpdir do |dir|
            first_root = File.join(dir, "a")
            second_root = File.join(dir, "b")
            Dir.mkdir_p(first_root)
            Dir.mkdir_p(second_root)

            base_file = File.join(first_root, "io.ds")
            File.write(base_file, "echo 1\n")

            other_file = File.join(second_root, "io.ds")
            File.write(other_file, "echo 2\n")

            config = Dragonstone::ModuleConfig.new([first_root, second_root])
            resolver = Dragonstone::ModuleResolver.new(config)
            item = Dragonstone::AST::UseItem.new(
                kind: Dragonstone::AST::UseItemKind::Paths,
                specs: ["io"]
            )

            resolver.expand_use_item(item, first_root, exclude_path: File.realpath(base_file)).should eq([
                File.realpath(other_file)
            ])
        end
    end

    it "attaches stdlib metadata onto module nodes" do
        with_tmpdir do |dir|
            dep_dir = File.join(dir, "dep")
            Dir.mkdir_p(dep_dir)
            File.write(File.join(dep_dir, "module.yml"), <<-YAML)
name: dep
entry: module.ds
requires: shared
YAML
            File.write(File.join(dep_dir, "module.ds"), <<-DS)
module dep
end
DS
            main = File.join(dir, "main.ds")
            File.write(main, %(use "./dep/module"))

            config = Dragonstone::ModuleConfig.new([dir])
            resolver = Dragonstone::ModuleResolver.new(config)
            resolver.resolve(main)

            node = resolver.graph.nodes.values.find { |candidate| candidate.canonical_path.ends_with?("module.ds") }
            node.should_not be_nil
            node.not_nil!.metadata.not_nil!.name.should eq("dep")
        end
    end

    it "rejects modules incompatible with the requested backend" do
        with_tmpdir do |dir|
            dep_dir = File.join(dir, "dep")
            Dir.mkdir_p(dep_dir)
            File.write(File.join(dep_dir, "module.yml"), <<-YAML)
name: files
entry: module.ds
requires: native
YAML
            File.write(File.join(dep_dir, "module.ds"), <<-DS)
module files
end
DS
            main = File.join(dir, "main.ds")
            File.write(main, %(use "./dep/module"))

            config = Dragonstone::ModuleConfig.new([dir], backend_mode: Dragonstone::BackendMode::Core)
            resolver = Dragonstone::ModuleResolver.new(config)

            expect_raises(Dragonstone::RuntimeError) do
                resolver.resolve(main)
            end
        end
    end
end
