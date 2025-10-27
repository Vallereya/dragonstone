require "spec"
require "../src/dragonstone/lib/interpreter/*"

describe Dragonstone::DragonModule do
  it "stores and looks up methods by string name" do
    mod = Dragonstone::DragonModule.new("TestMod")
    scope = {} of String => Dragonstone::ScopeValue
    type_scope = {} of String => Dragonstone::Typing::Descriptor
    params = [Dragonstone::AST::TypedParameter.new("x")]
    method = Dragonstone::MethodDefinition.new("bar", params, [] of Dragonstone::AST::Node, scope, type_scope)
    mod.define_method("bar", method)
    mod.lookup_method("bar").should_not be_nil
  end

  it "stores and reads constants by string name" do
    mod = Dragonstone::DragonModule.new("TestMod")
    mod.define_constant("PI", 3.14_f64)
    mod.constant?("PI").should be_true
    mod.fetch_constant("PI").should eq 3.14_f64
  end
end
