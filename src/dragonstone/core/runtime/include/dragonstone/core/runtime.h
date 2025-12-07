#pragma once
#include <stdint.h>
#include <stddef.h>
#include "dragonstone/core/version.h"

#ifdef RUBY_SUPPORT
#include "ruby.h"
#else

// If there's no Ruby.
typedef void* VALUE;
#define Qnil ((VALUE)0)
#define Qtrue ((VALUE)2)
#define Qfalse ((VALUE)0)
#define INT2NUM(x) ((VALUE)(long)(x))
#define LONG2NUM(x) ((VALUE)(long)(x))
#define DBL2NUM(x) ((VALUE)(long)(x))
#endif

/*
--------------------------------------------------------------------------------
Hybrid Runtime Core Types
--------------------------------------------------------------------------------
The Dragonstone runtime needs to juggle dynamic objects (scripting) and
primitive/struct payloads (physics/engine code).  These lightweight
definitions are shared between the interpreter, LLVM runtime stubs, and any
linked host runtimes so both sides speak the same ABI.
*/

typedef enum {
    DS_VALUE_TAG_NIL = 0,
    DS_VALUE_TAG_INT,
    DS_VALUE_TAG_FLOAT,
    DS_VALUE_TAG_BOOL,
    DS_VALUE_TAG_OBJECT,
    DS_VALUE_TAG_POINTER
} DSValueTag;

typedef struct {
    uint8_t type_tag;
    union {
        int64_t i64;
        double f64;
        void *ptr;
        uint8_t boolean;
    } as;
} DSValue;

typedef DSValue (*DSMethodThunk)(void *receiver, int64_t argc, const DSValue *argv);

typedef struct DSClass DSClass;

struct DSClass {
    const char *name;
    DSClass *parent;
    void **vtable;
    uint32_t vtable_size;
    uint32_t instance_size;
};

typedef struct {
    DSClass *klass;
    /* Instance data follows this header */
} DSObject;

DSObject *dragonstone_runtime_alloc_instance(DSClass *klass, size_t field_size);

typedef struct {
    const char *name;
    uint32_t offset;
    uint32_t size;
} DSStructField;

typedef struct {
    const char *name;
    uint32_t size;
    uint32_t field_count;
    const DSStructField *fields;
} DSStructLayout;

// Crystal -> C exports.
extern int ds_run_source(const char* src);

// Fetch constants (when Ruby support is enabled).
#ifdef RUBY_SUPPORT
extern VALUE ds_const_under(VALUE outer, const char* name);
#endif

// Crystal lexer/parser exports.
extern void* ds_lexer_new(const char* src);
extern void* ds_lexer_tokenize(void* lexer);
extern void* ds_parser_new(void* tokens);
extern void* ds_parser_parse(void* parser);

// Runtime state management.
typedef struct DSRuntime DSRuntime;

// Initialize the tri-language runtime.
DSRuntime* ds_runtime_init(void);
void ds_runtime_cleanup(DSRuntime* rt);
DSRuntime* ds_get_runtime(void);

/*

Dragonstone FFI
These allow Dragonstone code to call C/Ruby/Crystal.

*/

// Call C functions.
VALUE ds_ffi_call_c(const char* func_name, int argc, VALUE* argv);

// Call Ruby methods.
#ifdef RUBY_SUPPORT
VALUE ds_ffi_call_ruby(VALUE receiver, const char* method, int argc, VALUE* argv);
#endif

// Call Crystal functions.
VALUE ds_ffi_call_crystal(const char* func_name, int argc, VALUE* argv);

// Convert between language types.
VALUE ds_crystal_to_ruby(void* crystal_val);
void* ds_ruby_to_crystal(VALUE ruby_val);
VALUE ds_c_to_ruby(void* c_val, const char* type);

// Run a Dragonstone file.
int ds_run_file(const char* filename);

// Run Dragonstone code from a string.
int ds_run_string(const char* source);

// Start interactive REPL.
void ds_repl(void);

// Read file utility.
char* read_file(const char* filename, size_t* out_size);
