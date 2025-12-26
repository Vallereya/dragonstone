module Dragonstone
    class Interpreter
        private def get_variable(name : String, location : Location? = nil)
            binding_info = find_binding_with_scope(name)
            return unwrap_binding(binding_info[:value]) if binding_info

            constant_info = lookup_container_constant(name)
            return constant_info[:value] if constant_info[:found]

            runtime_error(NameError, "Undefined variable or constant: #{name}", location)
        end

        private def set_variable(name : String, value, location : Location? = nil, type_descriptor : Typing::Descriptor? = nil)
            binding_info = find_binding_with_scope(name)

            target_scope = current_scope
            scope_index = @scopes.size - 1

            if binding_info
                stored_value = binding_info[:value]

                if stored_value.is_a?(ConstantBinding)
                    runtime_error(ConstantError, "Cannot reassign constant #{name}", location)
                else
                    target_scope = binding_info[:scope]
                    scope_index = binding_info[:index]
                end
            elsif name.starts_with?("__ds_cvar_") || name.starts_with?("__ds_mvar_")
                target_scope = @scopes.first
                scope_index = 0
            end

            descriptor = nil
            if typing_enabled?
                descriptor = type_descriptor || type_descriptor_for_scope(scope_index, name)
                ensure_type!(descriptor, value, location) if descriptor
            end

            target_scope[name] = value

            assign_type_to_scope(scope_index, name, type_descriptor || descriptor) if typing_enabled?
            value
        end

        private def set_constant(name : String, value, location : Location? = nil)
            binding_info = find_binding_with_scope(name)
            if binding_info
                runtime_error(ConstantError, "Constant #{name} already defined", location)
            end
            current_scope[name] = ConstantBinding.new(value)
            value
        end

        private def define_container_constant(container : DragonModule, name : String, value, node : AST::Node)
            if container.constant?(name)
                runtime_error(ConstantError, "Constant #{name} already defined in #{container.name}", node)
            end
            container.define_constant(name, value)
            value
        end

        private def lookup_constant_value(name : String)
            constant_info = lookup_container_constant(name)
            return constant_info[:value] if constant_info[:found]

            binding = find_binding(name)
            unwrap_binding(binding) if binding
        end

        private def lookup_container_constant(name : String) : NamedTuple(found: Bool, value: RuntimeValue?)
            @container_stack.reverse_each do |container|
                if name == "self"
                    return {found: true, value: container}
                end
                if container.constant?(name)
                    return {found: true, value: container.fetch_constant(name)}
                end
            end
            {found: false, value: nil}
        end

        private def find_binding_with_scope(name : String)
            (@scopes.size - 1).downto(0) do |index|
                scope = @scopes[index]
                return {index: index, scope: scope, value: scope[name]?} if scope.has_key?(name)
            end
            nil
        end

        private def find_binding(name : String)
            info = find_binding_with_scope(name)
            info ? info[:value] : nil
        end

        private def unwrap_binding(binding)
            if binding.is_a?(ConstantBinding)
                binding.value
            else
                binding
            end
        end

        private def current_scope
            @scopes.last
        end

        private def current_type_scope
            @type_scopes.last
        end

        private def current_container
            @container_stack.last?
        end

        private def push_scope(scope : Scope, type_scope : TypeScope? = nil)
            @scopes << scope
            @type_scopes << (type_scope || new_type_scope)
        end

        private def pop_scope
            @scopes.pop
            @type_scopes.pop
        end

        private def with_container(container : DragonModule)
            @container_stack << container
            yield
        ensure
            @container_stack.pop
        end

        private def with_block(block : Function?, &block_proc)
            @block_stack << block
            begin
                yield
            ensure
                @block_stack.pop
            end
        end

        private def current_block : Function?
            @block_stack.last?
        end

        private def descriptor_for(expr : AST::TypeExpression) : Typing::Descriptor
            @descriptor_cache.fetch(expr)
        end

        private def ensure_type!(descriptor : Typing::Descriptor?, value, node_or_location = nil)
            return unless typing_enabled?
            return unless descriptor

            context = typing_context
            begin
                return if descriptor.satisfied_by?(value, context)
            rescue e : Typing::UnknownTypeError
                runtime_error(NameError, "Unknown type '#{e.type_name}'", node_or_location)
            rescue e : Typing::RecursiveAliasError
                runtime_error(TypeError, "Recursive alias '#{e.alias_name}' detected during type checking", node_or_location)
            end

            runtime_error(TypeError, "Expected #{descriptor.to_s}, got #{describe_runtime_value(value)}", node_or_location)
        end

        private def coerce_value_for_type(type_expr : AST::TypeExpression?, value, node_or_location = nil)
            return value unless type_expr
            simple = type_expr.as?(AST::SimpleTypeExpression)
            return value unless simple

            name = simple.name.downcase
            explicit_width = name == "int32" || name == "int64" || name == "float32" || name == "float64"
            return value unless typing_enabled? || explicit_width

            case name
            when "int32"
                coerce_int32(value, node_or_location)
            when "int64", "int", "integer"
                coerce_int64(value, node_or_location)
            when "float32"
                coerce_float32(value, node_or_location)
            when "float64", "float"
                coerce_float64(value, node_or_location)
            else
                value
            end
        end

        private def coerce_int32(value, node_or_location)
            case value
            when Int32
                value
            when Int64
                unless value >= Int32::MIN && value <= Int32::MAX
                    runtime_error(TypeError, "Expected int32, got #{describe_runtime_value(value)}", node_or_location)
                end
                value.to_i32
            when Float32
                coerce_float_to_int32(value.to_f64, node_or_location)
            when Float64
                coerce_float_to_int32(value, node_or_location)
            else
                runtime_error(TypeError, "Expected int32, got #{describe_runtime_value(value)}", node_or_location)
            end
        end

        private def coerce_int64(value, node_or_location)
            case value
            when Int64
                value
            when Int32
                value.to_i64
            when Float32
                coerce_float_to_int64(value.to_f64, node_or_location)
            when Float64
                coerce_float_to_int64(value, node_or_location)
            else
                runtime_error(TypeError, "Expected int64, got #{describe_runtime_value(value)}", node_or_location)
            end
        end

        private def coerce_float32(value, node_or_location)
            case value
            when Float32
                value
            when Float64
                value.to_f32
            when Int32
                value.to_f32
            when Int64
                value.to_f32
            else
                runtime_error(TypeError, "Expected float32, got #{describe_runtime_value(value)}", node_or_location)
            end
        end

        private def coerce_float64(value, node_or_location)
            case value
            when Float64
                value
            when Float32
                value.to_f64
            when Int32
                value.to_f64
            when Int64
                value.to_f64
            else
                runtime_error(TypeError, "Expected float64, got #{describe_runtime_value(value)}", node_or_location)
            end
        end

        private def coerce_float_to_int32(value : Float64, node_or_location)
            if value.nan? || value.infinite?
                runtime_error(TypeError, "Expected int32, got #{value}", node_or_location)
            end
            int_value = value.to_i64
            unless int_value >= Int32::MIN && int_value <= Int32::MAX
                runtime_error(TypeError, "Expected int32, got #{value}", node_or_location)
            end
            int_value.to_i32
        rescue OverflowError
            runtime_error(TypeError, "Expected int32, got #{value}", node_or_location)
        end

        private def coerce_float_to_int64(value : Float64, node_or_location)
            if value.nan? || value.infinite?
                runtime_error(TypeError, "Expected int64, got #{value}", node_or_location)
            end
            value.to_i64
        rescue OverflowError
            runtime_error(TypeError, "Expected int64, got #{value}", node_or_location)
        end

        private def ensure_descriptor_match!(descriptor : Typing::Descriptor?, value, node_or_location = nil)
            return unless descriptor

            context = typing_context
            begin
                return if descriptor.satisfied_by?(value, context)
            rescue e : Typing::UnknownTypeError
                runtime_error(NameError, "Unknown type '#{e.type_name}'", node_or_location)
            rescue e : Typing::RecursiveAliasError
                runtime_error(TypeError, "Recursive alias '#{e.alias_name}' detected during type checking", node_or_location)
            end

            runtime_error(TypeError, "Expected #{descriptor.to_s}, got #{describe_runtime_value(value)}", node_or_location)
        end

        private def typing_context : Typing::Context
            @typing_context ||= Typing::Context.new(
                ->(name : String) { lookup_constant_value(name) },
                ->(constant : RuntimeValue, value : RuntimeValue) { constant_type_match?(constant, value) },
                ->(name : String) { descriptor_for_alias(name) }
            )
        end

        private def constant_type_match?(constant : RuntimeValue, value : RuntimeValue)
            case constant
            when DragonClass
                if value.is_a?(DragonInstance)
                    within_hierarchy?(value.as(DragonInstance).klass, constant)
                elsif value.is_a?(DragonClass)
                    within_hierarchy?(value.as(DragonClass), constant)
                else
                    false
                end
            when DragonModule
                value.is_a?(DragonModule) && value == constant
            when Function
                value.is_a?(Function) && value == constant
            else
                value == constant
            end
        end

        private def current_self_instance(node : AST::Node) : DragonInstance
            self_value = current_scope["self"]?
            unless self_value && self_value.is_a?(DragonInstance)
                runtime_error(InterpreterError, "Instance variables can only be accessed inside instance methods", node)
            end
            self_value.as(DragonInstance)
        end

        private def set_instance_variable(instance : DragonInstance, name : String, value, node_or_location)
            if typing_enabled?
                if descriptor = resolve_instance_variable_descriptor(instance.klass, name)
                    ensure_type!(descriptor, value, node_or_location)
                end
            end
            instance.ivars[name] = value
        end

        private def resolve_instance_variable_descriptor(klass : DragonClass, name : String) : Typing::Descriptor?
            if descriptor = klass.ivar_type_descriptor(name)
                descriptor
            else
                if type_expr = klass.ivar_type_annotation(name)
                    descriptor = descriptor_for(type_expr)
                    klass.cache_ivar_descriptor(name, descriptor)
                    descriptor
                else
                    nil
                end
            end
        end

        private def define_accessor_methods(klass : DragonClass, macro_node : AST::AccessorMacro, entry : AST::AccessorEntry)
            location = macro_node.location
            case macro_node.kind
            when :getter
                define_getter_method(klass, entry, macro_node.visibility, location)
            when :setter
                define_setter_method(klass, entry, macro_node.visibility, location)
            when :property
                define_getter_method(klass, entry, macro_node.visibility, location)
                define_setter_method(klass, entry, macro_node.visibility, location)
            else
                runtime_error(InterpreterError, "Unknown accessor macro '#{macro_node.kind}'", macro_node)
            end
        end

        private def define_getter_method(klass : DragonClass, entry : AST::AccessorEntry, visibility : Symbol, location : Location?)
            body = [] of AST::Node
            body << AST::InstanceVariable.new(entry.name, location: location)
            method = build_method_definition(klass, entry.name, [] of AST::TypedParameter, body, entry.type_annotation, visibility)
            klass.define_method(entry.name, method)
        end

        private def define_setter_method(klass : DragonClass, entry : AST::AccessorEntry, visibility : Symbol, location : Location?)
            param = AST::TypedParameter.new("value", entry.type_annotation)
            value_var = AST::Variable.new("value", nil, location: location)
            assignment = AST::InstanceVariableAssignment.new(entry.name, value_var, location: location)
            body = [] of AST::Node
            body << assignment
            method = build_method_definition(klass, "#{entry.name}=", [param], body, entry.type_annotation, visibility)
            klass.define_method("#{entry.name}=", method)
        end

        private def build_method_definition(klass : DragonClass, name : String, typed_parameters : Array(AST::TypedParameter), body : Array(AST::Node), return_type : AST::TypeExpression?, visibility : Symbol) : MethodDefinition
            MethodDefinition.new(
                name,
                typed_parameters,
                body,
                current_scope.dup,
                current_type_scope.dup,
                klass,
                [] of AST::RescueClause,
                return_type,
                visibility: visibility
            )
        end

        private def ensure_method_visible!(receiver, method : MethodDefinition, node : AST::MethodCall, implicit_self : Bool)
            case method.visibility
            when :public
                return
            when :private
                runtime_error(InterpreterError, "Cannot call private method '#{method.name}' with an explicit receiver", node) unless implicit_self
            when :protected
                owner = method.owner
                unless owner.is_a?(DragonClass)
                    runtime_error(InterpreterError, "Cannot call protected method '#{method.name}' with an explicit receiver", node) unless implicit_self
                    return
                end

                owner_class = owner.as(DragonClass)
                caller_self = current_scope["self"]?
                unless caller_self && caller_self.is_a?(DragonInstance)
                    runtime_error(InterpreterError, "Protected method '#{method.name}' can only be called from within #{owner_class.name} or its subclasses", node)
                end

                caller_class = caller_self.as(DragonInstance).klass
                unless within_hierarchy?(caller_class, owner_class)
                    runtime_error(InterpreterError, "Protected method '#{method.name}' can only be called from within #{owner_class.name} or its subclasses", node)
                end

                if receiver.is_a?(DragonInstance)
                    receiver_class = receiver.as(DragonInstance).klass
                    unless within_hierarchy?(receiver_class, owner_class)
                        runtime_error(InterpreterError, "Protected method '#{method.name}' can only be called on instances of #{owner_class.name} or its subclasses", node)
                    end
                else
                    runtime_error(InterpreterError, "Cannot call protected method '#{method.name}' with an explicit receiver", node) unless implicit_self
                end
            else
                runtime_error(InterpreterError, "Unknown method visibility '#{method.visibility}'", node)
            end
        end

        private def within_hierarchy?(klass : DragonClass, ancestor : DragonClass) : Bool
            current = klass
            while current
                return true if current == ancestor
                current = current.superclass
            end
            false
        end

        private def describe_runtime_value(value)
            case value
            when DragonInstance
                "#{value.klass.name} instance"
            when DragonClass
                "#{value.name} class"
            when DragonModule
                "#{value.name} module"
            when Nil
                "nil"
            when TupleValue
                "Tuple"
            when NamedTupleValue
                "NamedTuple"
            when SymbolValue
                "Symbol"
            when BagConstructor
                value.to_s
            when BagValue
                "Bag"
            else
                value.class.name
            end
        end

        private def new_type_scope : TypeScope
            {} of String => Typing::Descriptor
        end

        private def register_type_alias(name : String, expr : AST::TypeExpression, node : AST::AliasDefinition)
            if @type_aliases.has_key?(name)
                runtime_error(NameError, "Type alias #{name} already defined", node)
            end
            @type_aliases[name] = expr
            @alias_descriptor_cache.delete(name)
        end

        private def find_type_alias(name : String) : AST::TypeExpression?
            @type_aliases[name]?
        end

        private def descriptor_for_alias(name : String) : Typing::Descriptor?
            expr = find_type_alias(name)
            return nil unless expr
            cached = @alias_descriptor_cache[name]?
            return cached if cached
            descriptor = descriptor_for(expr)
            @alias_descriptor_cache[name] = descriptor
            descriptor
        end

        private def assign_type_to_scope(index : Int32, name : String, descriptor : Typing::Descriptor?)
            scope = @type_scopes[index]
            if descriptor
                scope[name] = descriptor
            else
                scope.delete(name)
            end
        end

        private def type_descriptor_for_scope(index : Int32, name : String) : Typing::Descriptor?
            scope = @type_scopes[index]?
            scope ? scope[name]? : nil
        end

        private def runtime_error(klass, message : String, node_or_location = nil)
            location = case node_or_location
                when AST::Node
                    node_or_location.location
                when Location
                    node_or_location
                when Nil
                    nil
                else
                    node_or_location.as(Location?)
                end
            raise klass.new(message, location: location)
        end
    end
end
