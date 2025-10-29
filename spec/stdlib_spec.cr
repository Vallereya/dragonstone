require "spec"
require "../src/dragonstone"

describe "Dragonstone standard library" do
    it "loads bundled modules without DS_PATH" do
        Dir.mktmpdir do |dir|
            script = File.join(dir, "main.ds")
            File.write(script, <<-DS)
use "string_length"
puts string.length("Dragonstone")
DS

            result = Dragonstone.run_file(script)
            result.output.should contain("11")
        end
    end

    it "respects DS_PATH overrides" do
        Dir.mktmpdir do |dir|
            lib_dir = File.join(dir, "lib")
            Dir.mkdir(lib_dir)

            shim = File.join(lib_dir, "string_length.ds")
            File.write(shim, "puts \"custom\"\n")

            script = File.join(dir, "main.ds")
            File.write(script, "use \"string_length\"\n")

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
end