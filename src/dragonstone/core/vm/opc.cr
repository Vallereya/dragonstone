module Dragonstone
    module OPC
        NOP   = 0

        # Constants / Locals
        CONST           = 1     # [CONST, const_index]                                      -> push consts[const_index]
        LOAD            = 2     # [LOAD,  name_index]                                       -> push env[name_index]
        STORE           = 3     # [STORE, name_index]                                       -> env[name_index] = pop (and push value back)
        POP             = 41    # pop 1
        DUP             = 42    # duplicate top of stack

        # Arithmetic
        ADD             = 10
        SUB             = 11
        MUL             = 12
        DIV             = 13
        NEG             = 14
        POS             = 15

        # Comparisons
        EQ              = 20
        NE              = 21
        LT              = 22
        LE              = 23
        GT              = 24
        GE              = 25
        NOT             = 26
        BIT_NOT         = 27
        MOD             = 28
        BIT_AND         = 29
        BIT_OR          = 30
        BIT_XOR         = 31
        SHL             = 32
        SHR             = 33
        FLOOR_DIV       = 34
        CMP             = 37    # [CMP]                                                     -> pop rhs, pop lhs, push -1/0/1

        # Control Flow
        JMP             = 35    # [JMP,  target_index]
        JMPF            = 36    # [JMPF, target_index]                                      -> if pop is falsey, jump

        # IO / Misc
        ECHO            = 40    # [ECHO, argc]                                              -> consume argc items, emit line, push nil
        EECHO           = 101   # [EECHO, argc]                                             -> consume argc items, emit (no newline), push nil
        DEBUG_ECHO      = 52    # [DEBUG_ECHO, const_index]                                 -> format top of stack with const string
        DEBUG_EECHO     = 102   # [DEBUG_EECHO, const_index]                                -> accumulate debug output (no newline)
        TYPEOF          = 53    # TYPEOF                                                    -> replace top of stack with its type name string

        # Composite / Objects
        MAKE_ARRAY      = 55    # [MAKE_ARRAY, count]                                       -> pop count items -> push array
        INDEX           = 56    # INDEX                                                     -> pop index, pop object -> push object[index]
        TO_S            = 57    # TO_S                                                      -> pop value, push value.to_s
        CONCAT          = 58    # CONCAT                                                    -> pop rhs, pop lhs, push lhs + rhs
        MAKE_MAP        = 70    # [MAKE_MAP, count]                                         -> pop count * 2 items -> push map
        MAKE_TUPLE      = 71    # [MAKE_TUPLE, count]                                       -> pop count items -> push tuple
        MAKE_NAMED_TUPLE = 72   # [MAKE_NAMED_TUPLE, count]                                 -> pop count * 2 items -> push named tuple
        STORE_INDEX     = 73    # STORE_INDEX                                               -> pop value, pop index, pop object -> assign
        LOAD_CONST_PATH = 74    # [LOAD_CONST_PATH, const_index]                            -> resolve constant path segments stored in consts[const_index]
        LOAD_IVAR       = 75    # [LOAD_IVAR, name_index]                                   -> load @ivar from current self
        STORE_IVAR      = 76    # [STORE_IVAR, name_index]                                  -> store @ivar on current self
        PUSH_HANDLER    = 77    # [PUSH_HANDLER, rescue_ip, ensure_ip]                      -> push exception handler
        POP_HANDLER     = 78    # POP_HANDLER                                               -> pop handler stack
        LOAD_EXCEPTION  = 79    # LOAD_EXCEPTION                                            -> push current exception value
        RAISE           = 80    # RAISE                                                     -> pop value and raise exception
        CHECK_RETHROW   = 81    # CHECK_RETHROW                                             -> rethrow pending exception after ensure
        MAKE_MODULE     = 82    # [MAKE_MODULE, name_index]                                 -> push new module
        MAKE_CLASS      = 83    # [MAKE_CLASS, name_index, abstract_flag, super_const_idx]  -> push new class
        MAKE_STRUCT     = 84    # [MAKE_STRUCT, name_index]                                 -> push new struct
        MAKE_ENUM       = 85    # [MAKE_ENUM, name_index, value_method_const_idx]           -> push new enum
        ENTER_CONTAINER = 86    # ENTER_CONTAINER                                           -> use top of stack as current container
        EXIT_CONTAINER  = 87    # EXIT_CONTAINER                                            -> pop container context
        DEFINE_CONST    = 88    # [DEFINE_CONST, name_index]                                -> define constant in current container
        DEFINE_METHOD   = 89    # [DEFINE_METHOD, name_index]                               -> define method in current container
        DEFINE_ENUM_MEMBER = 90 # [DEFINE_ENUM_MEMBER, name_index, has_value]               -> define enum member; optional value on stack
        MAKE_RANGE      = 91    # [MAKE_RANGE, inclusive_flag]                              -> pop end, pop start, push range
        ENTER_LOOP      = 92    # [ENTER_LOOP, condition_ip, body_ip, exit_ip]              -> push loop context metadata
        EXIT_LOOP       = 93    # EXIT_LOOP                                                 -> pop loop context
        EXTEND_CONTAINER = 94   # EXTEND_CONTAINER                                          -> pop target container and extend current container with it

        # Functions & Calls
        CALL            = 50    # [CALL, argc, name_index]                                  -> call global function
        RET             = 51    # return from function using top-of-stack as result
        INVOKE          = 54    # [INVOKE, name_index, argc]                                -> call method on receiver
        MAKE_FUNCTION   = 59    # [MAKE_FUNCTION, name_index, signature_const, chunk_const] -> push closure
        MAKE_BLOCK      = 60    # [MAKE_BLOCK, signature_const, chunk_const]                -> push block literal
        HALT            = 61    # Terminate Execution

        # Block / Control flow helpers
        CALL_BLOCK      = 62    # [CALL_BLOCK, argc, name_index]                            -> call function with block
        INVOKE_BLOCK    = 63    # [INVOKE_BLOCK, name_index, argc]                          -> call method with block
        YIELD           = 64    # [YIELD, argc]                                             -> yield to current block
        BREAK_SIGNAL    = 65    # signal break out of the closest loop/enumerator
        NEXT_SIGNAL     = 66    # signal next (skip iteration)
        REDO_SIGNAL     = 67    # signal redo (retry current iteration)

        # Typing helpers
        DEFINE_TYPE_ALIAS = 68  # [DEFINE_TYPE_ALIAS, name_index, type_const]
        CHECK_TYPE      = 69    # [CHECK_TYPE, type_const]                                  -> ensure top-of-stack matches type
        RETRY           = 95    # RETRY                                                     -> restart current begin/rescue block
        DEFINE_SINGLETON_METHOD = 96 # DEFINE_SINGLETON_METHOD                              -> pop function and receiver, attach method to receiver
        LOAD_ARGV       = 97    # LOAD_ARGV                                                 -> push argv array
        INVOKE_SUPER    = 98    # [INVOKE_SUPER, argc]                                      -> invoke superclass method of current callable
        INVOKE_SUPER_BLOCK = 99 # [INVOKE_SUPER_BLOCK, argc]                                -> invoke superclass method with explicit block
        POW             = 100   # POW                                                       -> pop rhs, pop lhs, push lhs ** rhs
        LOAD_STDOUT     = 103   # LOAD_STDOUT                                               -> push builtin stdout stream
        LOAD_STDERR     = 104   # LOAD_STDERR                                               -> push builtin stderr stream
        LOAD_STDIN      = 105   # LOAD_STDIN                                                -> push builtin stdin stream
        LOAD_ARGC       = 106   # LOAD_ARGC                                                 -> push argc integer
        LOAD_ARGF       = 107   # LOAD_ARGF                                                 -> push builtin argf stream
        MAKE_PARA       = 108   # [MAKE_PARA, signature_const, chunk_const]                 -> push capturing para literal
    end
end
