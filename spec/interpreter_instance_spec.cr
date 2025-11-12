require "spec"
require "../src/dragonstone/shared/lexer/lexer"
require "../src/dragonstone/shared/parser/parser"
require "../src/dragonstone/native/interpreter/interpreter"

private def run_program(source : String, typing : Bool = false)
    tokens = Dragonstone::Lexer.new(source).tokenize
    ast = Dragonstone::Parser.new(tokens).parse
    interpreter = Dragonstone::Interpreter.new(false, typing)
    interpreter.interpret(ast)
end

describe "Case and select control flow" do
    it "matches ranges and classes using case" do
        source = <<-DS
        class Animal
            def speak
                "animal"
            end
        end

        class Dog < Animal
        end

        def classify(value)
            case value
            when 1..3
                "small"
            when Animal
                value.speak
            else
                "unknown"
            end
        end

        echo classify(2)
        echo classify(Dog.new)
        echo classify("x")
        DS

        run_program(source).should eq("small\nanimal\nunknown\n")
    end

    it "chooses the first ready branch in select" do
        source = <<-DS
        select
        when false
            echo "first"
        when true
            echo "second"
        else
            echo "fallback"
        end
        DS

        run_program(source).should eq("second\n")
    end
end

describe "Self types" do
    it "enforces return types that reference self" do
        source = <<-DS
        class Builder
            def clone_self : self
                self
            end

            def wrong_self : self
                "oops"
            end
        end

        Builder.new.clone_self
        Builder.new.wrong_self
        DS

        expect_raises(Dragonstone::TypeError) do
            run_program(source, typing: true)
        end
    end
end

describe "Module extension" do
    it "copies methods from the extended module" do
        source = <<-DS
        module Shared
            def hello
                "hi"
            end
        end

        module Greeter
            extend Shared
        end

        echo Greeter.hello
        DS

        run_program(source).should eq("hi\n")
    end
end

describe "Constant path resolution" do
    it "resolves nested constants and classes through scope resolution" do
        source = <<-DS
        module Outer
            module Inner
                VALUE = 99

                class Thing
                    def initialize
                    end

                    def greet
                        "hello"
                    end
                end
            end
        end

        echo Outer::Inner::VALUE
        thing = Outer::Inner::Thing.new
        echo thing.greet
        DS

        run_program(source).should eq("99\nhello\n")
    end

    it "prints enum members using their name" do
        source = <<-DS
        enum Color
            Red
            Green
        end

        echo Color::Green
        DS

        run_program(source).should eq("Green\n")
    end
end

describe "Interpreter instance variable support" do
    it "exposes instance state through generated getter" do
        source = <<-DS
        class Person
            getter name

            def initialize(@name)
            end
        end

        person = Person.new("Alice")
        echo person.name
        DS

        run_program(source).should eq("Alice\n")
    end

    it "updates state through property setter" do
        source = <<-DS
        class Counter
            property value: int

            def initialize(@value: int)
            end

            def bump(amount: int)
                self.value += amount
            end
        end

        counter = Counter.new(5)
        counter.bump(3)
        echo counter.value
        DS

        run_program(source, typing: true).should eq("8\n")
    end

    it "rejects invalid assignments based on property type" do
        source = <<-DS
        class Account
            property balance: int

            def initialize(@balance: int)
            end
        end

        account = Account.new(100)
        account.balance = "oops"
        DS

        expect_raises(Dragonstone::TypeError) do
            run_program(source, typing: true)
        end
    end

    it "prevents calling private methods with an explicit receiver" do
        source = <<-DS
        class BankAccount
            def initialize(balance)
                @balance = balance
            end

            private def balance
                @balance
            end

            def reveal
                balance
            end
        end

        account = BankAccount.new(50)
        echo account.reveal
        account.balance
        DS

        expect_raises(Dragonstone::InterpreterError) do
            run_program(source)
        end
    end
end
