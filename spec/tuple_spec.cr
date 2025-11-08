require "spec"
require "../src/dragonstone"

describe "tuple literals" do
    it "evaluates tuple indexing" do
        source = <<-DS
my_tuple = {1, "Hey", 'x'}
echo my_tuple[0]
echo my_tuple[1]
echo my_tuple[2]
DS
        result = Dragonstone.run(source)
        result.output.should eq "1\nHey\nx\n"
    end

    it "evaluates named tuples with symbol access" do
        source = <<-DS
person = {name: "V", age: 30}
echo person[:name]
echo person[:age]
DS
        result = Dragonstone.run(source)
        result.output.should eq "V\n30\n"
    end

    it "enforces typed named tuple entries when typing is enabled" do
        source = <<-DS
#! typed
person = {name: str = "V", age: int = 30}
echo person[:name]
echo person[:age]
DS
        result = Dragonstone.run(source, typed: true)
        result.output.should eq "V\n30\n"
    end

    it "raises when typed named tuple entries violate their annotation" do
        source = <<-DS
#! typed
person = {name: str = 1}
DS
        expect_raises(Dragonstone::TypeError) do
            Dragonstone.run(source, typed: true)
        end
    end
end
