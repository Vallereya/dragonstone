require "spec"
require "file_utils"

private def with_tmpdir(&block : String ->)
    base = File.join(Dir.current, "tmp_spec_#{Process.pid}_#{Random.new.rand(1_000_000)}")
    Dir.mkdir_p(base)
    begin
        yield base
    ensure
        FileUtils.rm_rf(base)
    end
end

private def expect_net_module_available(backend : BackendMode)
    with_tmpdir do |dir|
        script = File.join(dir, "net_ok.ds")
        File.write(script, <<-DS)
use "net"

server = net.server
handle = net::Native.listen_tcp("127.0.0.1", 0, net::DEFAULT_BACKLOG)
net::Native.close(handle)
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
            File.write(script, <<-DS)
use "strings/strings_length"
echo strings.length("Dragonstone")
DS
            result = Dragonstone.run_file(script)
            result.output.should contain("11")
        end
    end

    it "respects DS_PATH overrides" do
        with_tmpdir do |dir|
            lib_dir = File.join(dir, "lib")
            Dir.mkdir(lib_dir)

            shim_dir = File.join(lib_dir, "strings")
            Dir.mkdir_p(shim_dir)
            shim = File.join(shim_dir, "strings_length.ds")
            File.write(shim, <<-DS)
module strings
    def length(str)
        echo "custom"
        str.size
    end
end
DS
            script = File.join(dir, "main.ds")
            File.write(script, <<-DS)
use "strings/strings_length"
echo strings.length("Dragonstone")
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
        expect_net_module_available(BackendMode::Native)
    end

    it "exposes net helpers on the core backend" do
        expect_net_module_available(BackendMode::Core)
    end
end
