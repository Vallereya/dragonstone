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

        # Control Flow
        JMP             = 30    # [JMP,  target_index]
        JMPF            = 31    # [JMPF, target_index]                                      -> if pop is falsey, jump

        # IO / Misc
        ECHO            = 40    # [ECHO, argc]                                              -> consume argc items, emit line, push nil
        DEBUG_PRINT     = 52    # [DEBUG_PRINT, const_index]                                -> format top of stack with const string
        TYPEOF          = 53    # TYPEOF                                                    -> replace top of stack with its type name string

        # Composite / Objects
        MAKE_ARRAY      = 55    # [MAKE_ARRAY, count]                                       -> pop count items -> push array
        INDEX           = 56    # INDEX                                                     -> pop index, pop object -> push object[index]
        TO_S            = 57    # TO_S                                                      -> pop value, push value.to_s
        CONCAT          = 58    # CONCAT                                                    -> pop rhs, pop lhs, push lhs + rhs

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
    end
end
