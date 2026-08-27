require "spec"
require "../src/dragonstone/shared/runtime/ffi/ffi"
require "../src/dragonstone/shared/runtime/abi/abi"

private def dragonstone_binary : String
    root = File.expand_path(File.join(__DIR__, ".."))
    exe = File.join(root, "bin", "build", "dragonstone.exe")
    return exe if File.exists?(exe)
    File.join(root, "bin", "build", "dragonstone")
end

describe "ABI env_get" do
    it "is a name FFI.call dispatches, not a host-only one" do
        Dragonstone::FFI.call("env_get", ["DS_ABI_ENV_SPEC_DEFINITELY_UNSET"]).should be_nil
    end

    it "answers nil for an unset key on both doors" do
        key = "DS_ABI_ENV_SPEC_DEFINITELY_UNSET"
        ENV[key]?.should be_nil

        Dragonstone::FFI.call("env_get", [key]).should be_nil
        Dragonstone::FFI.call_crystal("env_get", [key]).should be_nil
    end

    it "agrees with the host door on an inherited variable" do
        abi = Dragonstone::FFI.call("env_get", ["PATH"])
        host = Dragonstone::FFI.call_crystal("env_get", ["PATH"])

        abi.should eq(host)
        abi.as(String).empty?.should be_false
    end

    it "requires a key" do
        expect_raises(Exception, /env_get requires argument 1/) do
            Dragonstone::FFI.call("env_get", [] of Dragonstone::FFI::InteropValue)
        end
    end

    it "spells an empty value differently from an unset one" do
        exe = dragonstone_binary
        File.exists?(exe).should be_true

        fixture = File.tempname("ds-abi-env", ".ds")
        File.write(fixture, <<-'DS')
        set   = ffi.call("env_get", ["DS_ABI_ENV_SPEC_EMPTY"])
        unset = ffi.call("env_get", ["DS_ABI_ENV_SPEC_DEFINITELY_UNSET"])
        echo "set=#{set.nil? ? "NIL" : "STR<#{set}>"}"
        echo "unset=#{unset.nil? ? "NIL" : "STR<#{unset}>"}"
        DS

        begin
            output = IO::Memory.new
            status = Process.run(
                exe,
                args: ["run", fixture],
                env: {"DS_ABI_ENV_SPEC_EMPTY" => ""},
                output: output,
                error: output
            )

            status.success?.should be_true
            output.to_s.should contain("set=STR<>")
            output.to_s.should contain("unset=NIL")
        ensure
            File.delete(fixture) if File.exists?(fixture)
        end
    end
end
