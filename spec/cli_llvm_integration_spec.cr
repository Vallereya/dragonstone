require "spec"
require "file_utils"
require "../src/dragonstone"
require "../src/dragonstone/cli/cli_build"

private def clang_available? : Bool
    io = IO::Memory.new
    Process.run("clang", args: ["--version"], output: io, error: io).success?
rescue File::NotFoundError
    false
end

describe Dragonstone::CLIBuild do
    it "links LLVM artifacts into an executable when clang is available" do
        pending!("clang is not available; skipping LLVM linking integration test") unless clang_available?

        dir = File.join("dev", "build", "spec", "cli_llvm_spec_#{Random::Secure.hex(8)}")
        FileUtils.mkdir_p(dir)
        begin
            source = File.join(dir, "sample.ds")
            File.write(source, "echo \"llvm cli\"")

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            Dragonstone::CLIBuild.build_command(["--target", "llvm", "--output", dir, source], stdout, stderr).should eq(0)

            binary = File.join(dir, "dragonstone_llvm#{Dragonstone::CLIBuild::EXECUTABLE_SUFFIX}")
            File.exists?(binary).should be_true
        ensure
            FileUtils.rm_rf(dir)
        end
    end
end
