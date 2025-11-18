require "spec"
require "../src/dragonstone"

describe "core backend execution" do
    it "evaluates array enumerators with block control flow" do
        source = <<-DS
numbers = [1, 2, 3, 4]
sum = 0

numbers.each do |n|
    next if n == 2
    sum += n
    break if n == 3
end

echo sum

mapped = numbers.map do |n|
    next if n <= 1
    break if n == 4
    n * 10
end

echo mapped.length
echo mapped.first
echo mapped.last
DS
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "4\n2\n20\n30\n"
    end

    it "retries array iterations when redo is invoked" do
        source = <<-DS
values = [1, 2, 3]
sum = 0
redo_used = false

values.each do |value|
    if value == 2 && !redo_used
        redo_used = true
        redo
    end

    sum += value
end

echo sum
echo redo_used
DS
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "6\ntrue\n"
    end

    it "handles typed bags under the core backend" do
        source = <<-DS
#! typed
numbers = bag(int).new
numbers.add(1)
numbers.add(2)
numbers.add(3)

sum = 0
numbers.each do |value|
    next if value == 1
    sum += value
    break if value == 3
end

echo sum

product = numbers.inject(1) do |memo, value|
    memo * value
end

echo product
DS
        result = Dragonstone.run(source, typed: true, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "5\n6\n"
    end

    it "enforces typed assignments when running on the core backend" do
        source = <<-DS
#! typed
name: str = 1
DS
        expect_raises(Dragonstone::TypeError) do
            Dragonstone.run(source, typed: true, backend: Dragonstone::BackendMode::Core)
        end
    end
end
