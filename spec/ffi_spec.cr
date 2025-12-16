require "spec"
require "../src/dragonstone/cli/cli"

describe "Dragonstone FFI" do
    it "runs the interop example successfully" do
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Dragonstone::CLI.run(["run", "examples/other/interop.ds"], stdout, stderr)

        status.should eq(0)
        stderr.to_s.should be_empty
    end
end
