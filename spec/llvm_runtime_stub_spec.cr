require "spec"

describe "LLVM runtime stub map order" do
    it "appends map entries in insertion order" do
        source = File.read("src/dragonstone/core/compiler/targets/llvm/llvm_runtime.c")
        source.includes?("ds_map_append_entry").should be_true
        source.includes?("ds_map_append_entry(map, keys[i], values[i]);").should be_true
    end

    it "formats map display with arrow separators" do
        source = File.read("src/dragonstone/core/compiler/targets/llvm/llvm_runtime.c")
        source.includes?(" -> ").should be_true
    end
end

describe "LLVM runtime stub unicode shims" do
    it "includes unicode call_crystal handlers" do
        source = File.read("src/dragonstone/core/compiler/targets/llvm/llvm_runtime.c")
        source.includes?("unicode_normalize").should be_true
        source.includes?("unicode_casefold").should be_true
        source.includes?("unicode_grapheme_count").should be_true
        source.includes?("unicode_general_category").should be_true
        source.includes?("unicode_compare").should be_true
    end

    it "uses utf8proc for unicode operations" do
        source = File.read("src/dragonstone/core/compiler/targets/llvm/llvm_runtime.c")
        source.includes?("utf8proc_").should be_true
    end
end

describe "LLVM backend inspect formatting" do
    it "declares an inspect runtime hook" do
        source = File.read("src/dragonstone/core/compiler/targets/llvm/backend.cr")
        source.includes?("inspect_value: \"dragonstone_runtime_value_inspect\"").should be_true
    end

    it "uses inspect for debug echo output" do
        source = File.read("src/dragonstone/core/compiler/targets/llvm/backend.cr")
        source.includes?("func = inspect ? @runtime[:inspect_value] : @runtime[:to_string]").should be_true
    end
end
