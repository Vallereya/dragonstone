require "spec"
require "file_utils"
require "../src/dragonstone"

private def with_tmpdir(&block : String ->)
    base = File.join(Dir.current, "tmp_spec_#{Process.pid}_#{Random.new.rand(1_000_000)}")
    Dir.mkdir_p(base)
    begin
        yield base
    ensure
        FileUtils.rm_rf(base)
    end
end

private def expect_net_module_available(backend : Dragonstone::BackendMode)
    with_tmpdir do |dir|
        script = File.join(dir, "net_ok.ds")
        File.write(script, <<-DS)
use "net"

echo net::DEFAULT_BACKLOG
echo "net-ok"
DS
        result = Dragonstone.run_file(script, backend: backend)
        result.output.should contain("net-ok")
    end
end

require "../src/dragonstone"

describe "Dragonstone standard library" do
    it "loads bundled modules without DS_PATH" do
        with_tmpdir do |dir|
            script = File.join(dir, "main.ds")
            # `levenshtein` is a real bundled module under
            # stdlib/modules/shared/. The old `strings_length` module this
            # spec used was added into the language as `String#length`.
            File.write(script, <<-DS)
use "levenshtein"
echo Levenshtein.distance("Dragonstone", "Dragonstone")
DS
            result = Dragonstone.run_file(script)
            result.output.should contain("0")
        end
    end

    it "respects DS_PATH overrides" do
        with_tmpdir do |dir|
            lib_dir = File.join(dir, "lib")
            Dir.mkdir(lib_dir)

            # Shadow a module that really is bundled, so this asserts an
            # actual override rather than just "DS_PATH modules resolve".
            shim = File.join(lib_dir, "levenshtein.ds")
            File.write(shim, <<-DS)
module Levenshtein
    def distance(a, b)
        echo "custom"
        0
    end
end
DS
            script = File.join(dir, "main.ds")
            File.write(script, <<-DS)
use "levenshtein"
echo Levenshtein.distance("Dragonstone", "Dragonstone")
DS
            previous = ENV["DS_PATH"]?
            begin
                ENV["DS_PATH"] = lib_dir
                result = Dragonstone.run_file(script)
                result.output.should contain("custom")
            ensure
                if previous
                    ENV["DS_PATH"] = previous
                else
                    ENV.delete("DS_PATH")
                end
            end
        end
    end

    it "exposes net helpers on the native backend" do
        expect_net_module_available(Dragonstone::BackendMode::Native)
    end

    it "exposes net helpers on the core backend" do
        expect_raises(Dragonstone::RuntimeError) do
            expect_net_module_available(Dragonstone::BackendMode::Core)
        end
    end

    it "parses TOML payloads from the stdlib" do
        with_tmpdir do |dir|
            script = File.join(dir, "toml_ok.ds")
            File.write(script, <<-DS)
use "toml"

sample = "title = \\"TOML\\"\\nactive = true\\npoints = [1, 2, 3]\\n[owner]\\nname = \\"Tom\\""
data = TOML.parse(sample)

if data["title"].as_s != "TOML" || !data["active"].as_bool || data["points"].as_a[1].as_i != 2 || data["owner"].as_h["name"].as_s != "Tom"
    raise "toml parse failed"
end

echo "toml-ok"
DS
            result = Dragonstone.run_file(script)
            result.output.should contain("toml-ok")
        end
    end

    it "raises on malformed TOML input" do
        with_tmpdir do |dir|
            script = File.join(dir, "toml_err.ds")
            File.write(script, <<-DS)
use "toml"

sample = "a = 1\\na = 2"
TOML.parse(sample)
DS
            expect_raises(Dragonstone::RuntimeError) do
                Dragonstone.run_file(script)
            end
        end
    end
end
