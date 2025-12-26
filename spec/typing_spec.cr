require "spec"
require "../src/dragonstone"

describe "optional typing" do
    it "raises when an annotated assignment is violated" do
        source = <<-DS
#! typed
name: str = 1
DS
        expect_raises(Dragonstone::TypeError) do
            Dragonstone.run(source, typed: true)
        end
    end

    it "allows union and optional annotations" do
        source = <<-DS
#! typed
def greet(name: str | nil) -> str
  if name == nil
    "hi"
  else
    "hi \#{name}"
  end
end

greet(nil)
greet("Arya")
DS
        result = Dragonstone.run(source, typed: true)
        result.output.should eq ""
    end

    it "does not enforce annotations when typing is disabled" do
        source = <<-DS
name: int = "oops"
DS
        Dragonstone.run(source, typed: false).output.should eq ""
    end

    it "supports generic type aliases" do
        success_source = <<-DS
#! typed
alias Data = Array(str) | Hash(str, int)

def process(data: Data)
  data
end

process(["first", "second"])
process({ "age" -> 32 })
DS
        Dragonstone.run(success_source, typed: true).output.should eq ""

        failure_source = <<-DS
#! typed
alias Names = Array(str)

def handle(names: Names)
  names
end

handle([1, 2, 3])
DS
        expect_raises(Dragonstone::TypeError) do
            Dragonstone.run(failure_source, typed: true)
        end
    end

    it "supports explicit numeric width names" do
        int32_matcher = Dragonstone::Typing::Builtins.matcher_for("int32")
        int64_matcher = Dragonstone::Typing::Builtins.matcher_for("int64")
        float32_matcher = Dragonstone::Typing::Builtins.matcher_for("float32")
        float64_matcher = Dragonstone::Typing::Builtins.matcher_for("float64")

        int32_matcher.not_nil!.call(1_i32).should be_true
        int32_matcher.not_nil!.call(1_i64).should be_false

        int64_matcher.not_nil!.call(1_i64).should be_true
        int64_matcher.not_nil!.call(1_i32).should be_false

        float32_matcher.not_nil!.call(1.0_f32).should be_true
        float32_matcher.not_nil!.call(1.0_f64).should be_false

        float64_matcher.not_nil!.call(1.0_f64).should be_true
        float64_matcher.not_nil!.call(1.0_f32).should be_false
    end

    it "rejects non-numeric values for numeric annotations" do
        source = <<-DS
#! typed
value: float32 = "nope"
DS
        expect_raises(Dragonstone::TypeError) do
            Dragonstone.run(source, typed: true)
        end
    end
end
