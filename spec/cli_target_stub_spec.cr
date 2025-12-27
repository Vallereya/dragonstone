require "spec"
require "file_utils"
require "../src/dragonstone/cli/cli_build"

private def write_source(dir : String, name : String, content : String) : String
    FileUtils.mkdir_p(dir)
    path = File.join(dir, name)
    File.write(path, content)
    path
end

private def expected_artifact(dir : String, target : String, extension : String) : String
    File.join(dir, "dragonstone_#{target}.#{extension}")
end

describe "CLI build target stubs" do
    it "builds a Python target artifact" do
        dir = File.join(".cache", "spec_output", "cli_python_target_#{Random::Secure.hex(6)}")
        source = write_source(dir, "sample.ds", "echo \"hello\"")

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Dragonstone::CLIBuild.build_command(["--target", "python", "--output", dir, source], stdout, stderr)
        status.should eq(0)

        artifact = expected_artifact(dir, "python", "py")
        File.exists?(artifact).should be_true
    ensure
        FileUtils.rm_rf(dir)
    end

    it "builds a JavaScript target artifact" do
        dir = File.join(".cache", "spec_output", "cli_js_target_#{Random::Secure.hex(6)}")
        source = write_source(dir, "sample.ds", "echo \"hello\"")

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Dragonstone::CLIBuild.build_command(["--target", "javascript", "--output", dir, source], stdout, stderr)
        status.should eq(0)

        artifact = expected_artifact(dir, "javascript", "js")
        File.exists?(artifact).should be_true
    ensure
        FileUtils.rm_rf(dir)
    end
end
