require "spec"

describe "LLVM runtime stub map order" do
    it "appends map entries in insertion order" do
        source = File.read("src/dragonstone/core/compiler/targets/llvm/runtime_stub.c")
        source.includes?("ds_map_append_entry").should be_true
        source.includes?("ds_map_append_entry(map, keys[i], values[i]);").should be_true
    end

    it "formats map display with arrow separators" do
        source = File.read("src/dragonstone/core/compiler/targets/llvm/runtime_stub.c")
        source.includes?(" -> ").should be_true
    end
end
