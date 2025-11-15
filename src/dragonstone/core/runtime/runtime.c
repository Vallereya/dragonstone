#include "dragonstone/core/runtime.h"
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <stdio.h>

// Runtime state.
struct DSRuntime {
    void* crystal_state;
    VALUE ruby_state;
    void* c_state;
    void* dl_handle;
};

// Global runtime instance.
static DSRuntime* global_runtime = NULL;

// Initialize interop runtime.
DSRuntime* ds_runtime_init(void) {
    DSRuntime* rt = malloc(sizeof(DSRuntime));
    
    // Initialize Ruby state (only if theres Ruby).
    #ifdef RUBY_INIT_REQUIRED
    ruby_init();
    rt->ruby_state = rb_cObject;

    #else
    rt->ruby_state = NULL;

    #endif
    
    // Initialize Crystal state.
    rt->crystal_state = NULL;
    
    // Initialize C state.
    rt->c_state = NULL;
    
    // Open current process.
    rt->dl_handle = dlopen(NULL, RTLD_NOW);

    if (!rt->dl_handle) {
        fprintf(stderr, "Warning: Could not open dynamic symbol table: %s\n", dlerror());
    }
    
    return rt;
}

void ds_runtime_cleanup(DSRuntime* rt) {
    if (!rt) return;
    
    if (rt->dl_handle) {
        dlclose(rt->dl_handle);
    }
    
    #ifdef RUBY_INIT_REQUIRED
    ruby_cleanup(0);

    #endif
    
    free(rt);
}

// Get or create global runtime.
DSRuntime* ds_get_runtime(void) {
    if (!global_runtime) {
        global_runtime = ds_runtime_init();
    }
    return global_runtime;
}

/*

Dragonstone FFI

*/

// Dragonstone -> C
VALUE ds_ffi_call_c(const char* func_name, int argc, VALUE* argv) {
    DSRuntime* rt = ds_get_runtime();
    
    if (!rt->dl_handle) {

        #ifdef RUBY_INIT_REQUIRED
        rb_raise(rb_eRuntimeError, "Symbol table not available");

        #else
        fprintf(stderr, "Error: Symbol table not available\n");

        #endif
        return Qnil;
    }
    
    void* func_ptr = dlsym(rt->dl_handle, func_name);
    if (!func_ptr) {

        #ifdef RUBY_INIT_REQUIRED
        rb_raise(rb_eNameError, "C function '%s' not found: %s", func_name, dlerror());

        #else
        fprintf(stderr, "Error: C function '%s' not found: %s\n", func_name, dlerror());

        #endif
        return Qnil;
    }
    
    typedef int (*func_t)(void);

    func_t func = (func_t)func_ptr;

    int result = func();
    
    return INT2NUM(result);
}

// Dragonstone -> Ruby
VALUE ds_ffi_call_ruby(VALUE receiver, const char* method, int argc, VALUE* argv) {
    
    #ifdef RUBY_INIT_REQUIRED
    ID method_id = rb_intern(method);
    return rb_funcallv(receiver, method_id, argc, argv);

    #else
    fprintf(stderr, "Error: Ruby not initialized\n");
    return Qnil;

    #endif
}

// Dragonstone -> Crystal
VALUE ds_ffi_call_crystal(const char* func_name, int argc, VALUE* argv) {
    DSRuntime* rt = ds_get_runtime();
    
    void* func_ptr = dlsym(rt->dl_handle, func_name);

    if (!func_ptr) {
        #ifdef RUBY_INIT_REQUIRED

        rb_raise(rb_eNameError, "Crystal function '%s' not found: %s", func_name, dlerror());
        #else

        fprintf(stderr, "Error: Crystal function '%s' not found: %s\n", func_name, dlerror());
        #endif

        return Qnil;
    }
    
    typedef VALUE (*crystal_func_t)(int, VALUE*);

    crystal_func_t func = (crystal_func_t)func_ptr;

    return func(argc, argv);
}

VALUE ds_crystal_to_ruby(void* crystal_val) {
    // Convert Crystal to Ruby.
    return (VALUE)crystal_val;
}

void* ds_ruby_to_crystal(VALUE ruby_val) {
    // Convert Ruby to Crystal.
    return (void*)ruby_val;
}

VALUE ds_c_to_ruby(void* c_val, const char* type) {
    if (strcmp(type, "int") == 0) {
        return INT2NUM(*(int*)c_val);

    } else if (strcmp(type, "long") == 0) {
        return LONG2NUM(*(long*)c_val);

    } else if (strcmp(type, "double") == 0) {
        return DBL2NUM(*(double*)c_val);

    } else if (strcmp(type, "string") == 0) {
        return rb_str_new_cstr((char*)c_val);

    } else if (strcmp(type, "bool") == 0) {
        return *(int*)c_val ? Qtrue : Qfalse;

    }
    return Qnil;
}

// Read file converts to string for now.
char* read_file(const char* filename, size_t* out_size) {

    FILE* f = fopen(filename, "rb");

    if (!f) {
        perror("fopen");
        return NULL;
    }
    
    // Get file size.
    fseek(f, 0, SEEK_END);

    long size = ftell(f);

    fseek(f, 0, SEEK_SET);
    
    // Allocate buffer.
    char* content = malloc(size + 1);

    if (!content) {
        fclose(f);
        return NULL;
    }
    
    // Read content.
    size_t read_size = fread(content, 1, size, f);
    content[read_size] = '\0';
    fclose(f);
    
    if (out_size) {
        *out_size = read_size;
    }
    
    return content;
}

// Run Dragonstone file.
int ds_run_file(const char* filename) {
    size_t size;

    char* source = read_file(filename, &size);
    
    if (!source) {
        fprintf(stderr, "Error: Could not read file '%s'\n", filename);
        return 1;
    }
    
    int result = ds_run_source(source);
    
    free(source);
    return result;
}

int ds_run_string(const char* source) {
    return ds_run_source(source);
}

// REPL
void ds_repl(void) {

    char line[4096];
    
    printf("Dragonstone REPL v%s\n", DRAGONSTONE_VERSION);

    printf("Type 'exit' or press Ctrl + D to quit\n\n");
    
    while (1) {
        printf("ds> ");

        fflush(stdout);
        
        if (!fgets(line, sizeof(line), stdin)) {
            printf("\n");
            break;
        }
        
        size_t len = strlen(line);
        if (len > 0 && line[len - 1] == '\n') {
            line[len - 1] = '\0';
        }
        
        if (strcmp(line, "exit") == 0 || strcmp(line, "quit") == 0) {
            break;
        }
        
        if (strlen(line) == 0) {
            continue;
        }
        
        ds_run_string(line);
    }
    
    printf("REPL Closed.\n");
}

/*

Main Entry

*/

int main(int argc, char** argv) {

    // Initialize runtime.
    DSRuntime* rt = ds_runtime_init();

    global_runtime = rt;
    
    int result = 0;
    
    if (argc < 2) {
        // Start REPL
        ds_repl();

    } else if (argc == 2 && strcmp(argv[1], "-e") == 0) {
        // Error for -e flag but no code
        fprintf(stderr, "Error: -e requires code argument\n");
        fprintf(stderr, "Usage: %s [-e CODE] [FILE]\n", argv[0]);
        result = 1;

    } else if (argc == 3 && strcmp(argv[1], "-e") == 0) {
        // Execute inline code: dragonstone -e "print 42"
        result = ds_run_string(argv[2]);

    } else if (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-v") == 0) {
        // Print version.
        printf("Dragonstone %s\n", DRAGONSTONE_VERSION);

    } else if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        // Print help.
        printf("The Dragonstone Programming Language\n\n");
        printf("Usage:\n");
        printf("  %s [FILE]           Run a Dragonstone file\n", argv[0]);
        printf("  %s -e CODE          Execute inline code\n", argv[0]);
        printf("  %s                  Start REPL\n", argv[0]);
        printf("  %s --version        Print version\n", argv[0]);
        printf("  %s --help           Show help\n", argv[0]);

    } else {
        result = ds_run_file(argv[1]);

    }
    
    ds_runtime_cleanup(rt);

    global_runtime = NULL;
    
    return result;
}
