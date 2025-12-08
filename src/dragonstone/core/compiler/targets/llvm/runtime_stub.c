#define _CRT_SECURE_NO_WARNINGS
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_MSC_VER)
#define NORETURN __declspec(noreturn)
#else
#define NORETURN __attribute__((noreturn))
#endif

#define DS_BOX_MAGIC 0x4453564cU

typedef enum {
    DS_VALUE_INT32,
    DS_VALUE_INT64,
    DS_VALUE_BOOL,
    DS_VALUE_FLOAT,
    DS_VALUE_STRUCT,
    DS_VALUE_ARRAY
} DSValueKind;

typedef struct {
    uint32_t magic;
    DSValueKind kind;
    union {
        int32_t i32;
        int64_t i64;
        bool boolean;
        double f64;
        void* ptr;
    } as;
} DSValue;

typedef struct {
    int64_t length;
    void **items;
} DSArray;

static DSValue *ds_new_box(DSValueKind kind);
static char *ds_strdup(const char *input);
void *dragonstone_runtime_value_display(void *value);

void *dragonstone_runtime_box_i32(int32_t v);
void *dragonstone_runtime_box_i64(int64_t v);
void *dragonstone_runtime_box_bool(int32_t v);
void *dragonstone_runtime_box_float(double v);
void *dragonstone_runtime_array_push(void *array_val, void *value);

static void *ds_alloc(size_t size) {
    void *buffer = calloc(1, size);
    if (!buffer) {
        fprintf(stderr, "[fatal] Out of memory\n");
        abort();
    }
    return buffer;
}

static DSValue *ds_new_box(DSValueKind kind) {
    DSValue *value = (DSValue *)ds_alloc(sizeof(DSValue));
    value->magic = DS_BOX_MAGIC;
    value->kind = kind;
    return value;
}

static bool ds_is_boxed(void *value) {
    if (!value) return false;
    DSValue *box = (DSValue *)value;
    return box->magic == DS_BOX_MAGIC;
}

static char *ds_concat_segments(int64_t length, void **segments) {
    if (length <= 0) return ds_strdup("");
    
    size_t total_len = 0;
    for (int64_t i = 0; i < length; ++i) {
        if (segments[i]) total_len += strlen((const char*)segments[i]);
    }
    
    char *result = (char *)ds_alloc(total_len + 1);
    char *cursor = result;
    for (int64_t i = 0; i < length; ++i) {
        if (segments[i]) {
            size_t len = strlen((const char*)segments[i]);
            memcpy(cursor, segments[i], len);
            cursor += len;
        }
    }
    *cursor = '\0';
    return result;
}

static bool ds_compare_strings(const char *lhs, const char *rhs) {
    if (!lhs || !rhs) return false;
    return strcmp(lhs, rhs) == 0;
}

static DSValue *ds_create_array_box(int64_t length, void **elements) {
    DSArray *array = (DSArray *)ds_alloc(sizeof(DSArray));
    array->length = length;
    if (length > 0) {
        array->items = (void **)ds_alloc(sizeof(void *) * (size_t)length);
        if (elements) {
            for (int64_t i = 0; i < length; ++i) {
                array->items[i] = elements[i];
            }
        }
    } else {
        array->items = NULL;
    }
    
    DSValue *box = ds_new_box(DS_VALUE_ARRAY);
    box->as.ptr = array;
    return box;
}

static DSArray *ds_unwrap_array(void *value) {
    if (!value || !ds_is_boxed(value)) return NULL;
    DSValue *box = (DSValue *)value;
    if (box->kind != DS_VALUE_ARRAY) return NULL;
    return (DSArray *)box->as.ptr;
}

void *dragonstone_runtime_interpolated_string(int64_t length, void **segments) {
    return ds_concat_segments(length, segments);
}

_Bool dragonstone_runtime_case_compare(void *lhs, void *rhs) {
    if (lhs == rhs) return true;
    
    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *left = (DSValue *)lhs;
        DSValue *right = (DSValue *)rhs;
        if (left->kind != right->kind) return false;
        
        switch (left->kind) {
            case DS_VALUE_INT32: return left->as.i32 == right->as.i32;
            case DS_VALUE_INT64: return left->as.i64 == right->as.i64;
            case DS_VALUE_FLOAT: return left->as.f64 == right->as.f64;
            case DS_VALUE_BOOL:  return left->as.boolean == right->as.boolean;
            case DS_VALUE_ARRAY: return left->as.ptr == right->as.ptr;
            default: return false;
        }
    }
    
    if (!ds_is_boxed(lhs) && !ds_is_boxed(rhs)) {
        return ds_compare_strings((const char*)lhs, (const char*)rhs);
    }

    return false;
}

void *dragonstone_runtime_array_literal(int64_t length, void **elements) {
    return ds_create_array_box(length, elements);
}

void *dragonstone_runtime_array_push(void *array_val, void *value) {
    DSArray *array = ds_unwrap_array(array_val);
    if (!array) {
        fprintf(stderr, "[runtime] array_push called on non-array\n");
        return array_val;
    }
    
    int64_t new_len = array->length + 1;
    void **new_items = (void **)realloc(array->items, sizeof(void *) * new_len);
    if (!new_items) abort();
    
    array->items = new_items;
    array->items[array->length] = value;
    array->length = new_len;
    
    return array_val;
}

void *dragonstone_runtime_index_get(void *object, void *index_value) {
    DSArray *array = ds_unwrap_array(object);
    if (!array) return NULL;
    
    int64_t idx = 0;
    if (ds_is_boxed(index_value)) {
        DSValue *ibox = (DSValue *)index_value;
        if (ibox->kind == DS_VALUE_INT32) idx = ibox->as.i32;
        else if (ibox->kind == DS_VALUE_INT64) idx = ibox->as.i64;
    } else {
        return NULL;
    }
    
    if (idx < 0) idx = array->length + idx;
    if (idx < 0 || idx >= array->length) return NULL;
    
    return array->items[idx];
}

void *dragonstone_runtime_index_set(void *object, void *index_value, void *value) {
    DSArray *array = ds_unwrap_array(object);
    if (!array) return NULL;

    int64_t idx = 0;
    if (ds_is_boxed(index_value)) {
        DSValue *ibox = (DSValue *)index_value;
        if (ibox->kind == DS_VALUE_INT32) idx = ibox->as.i32;
        else if (ibox->kind == DS_VALUE_INT64) idx = ibox->as.i64;
    }
    
    if (idx < 0) idx = array->length + idx;
    
    if (idx >= array->length) {
        int64_t new_len = idx + 1;
        void **new_items = realloc(array->items, sizeof(void*) * new_len);
        if(!new_items) abort();
        for(int64_t i = array->length; i < new_len; i++) new_items[i] = NULL;
        
        array->items = new_items;
        array->length = new_len;
    }
    
    if (idx >= 0) {
        array->items[idx] = value;
    }
    return value;
}

void *dragonstone_runtime_method_invoke(void *receiver, void *method_name_ptr, int64_t argc, void **argv) {
    const char *method = (const char *)method_name_ptr;
    
    if (ds_is_boxed(receiver)) {
        DSValue *box = (DSValue *)receiver;
        
        if (box->kind == DS_VALUE_ARRAY) {
            DSArray *arr = (DSArray *)box->as.ptr;
            
            if (strcmp(method, "length") == 0 || strcmp(method, "size") == 0 || strcmp(method, "count") == 0) {
                return (void *)dragonstone_runtime_box_i64(arr->length);
            }
            if (strcmp(method, "first") == 0) {
                if (arr->length == 0) return NULL;
                return arr->items[0];
            }
            if (strcmp(method, "last") == 0) {
                if (arr->length == 0) return NULL;
                return arr->items[arr->length - 1];
            }
            if (strcmp(method, "empty") == 0 || strcmp(method, "empty?") == 0) {
                return (void *)dragonstone_runtime_box_bool(arr->length == 0);
            }
            if (strcmp(method, "pop") == 0) {
                if (arr->length == 0) return NULL;
                void *val = arr->items[arr->length - 1];
                arr->length--; 
                return val;
            }
            if (strcmp(method, "push") == 0 || strcmp(method, "<<") == 0) {
                if (argc > 0) dragonstone_runtime_array_push(receiver, argv[0]);
                return receiver;
            }
        }
    }
    
    fprintf(stderr, "[runtime] Method not found: %s\n", method);
    return NULL;
}

static const char DS_STR_NIL_VAL[] = "nil";
static const char DS_STR_TRUE_VAL[] = "true";
static const char DS_STR_FALSE_VAL[] = "false";

static char *ds_strdup(const char *input) {
    if (!input) return NULL;
    size_t len = strlen(input);
    char *copy = (char *)ds_alloc(len + 1);
    memcpy(copy, input, len + 1);
    return copy;
}

static char *ds_format_value(void *value, bool quote_strings) {
    if (!value) return (void *)DS_STR_NIL_VAL;
    
    if (ds_is_boxed(value)) {
        DSValue *box = (DSValue *)value;
        switch (box->kind) {
            case DS_VALUE_INT32: {
                char buf[32]; snprintf(buf, 32, "%d", box->as.i32); return ds_strdup(buf);
            }
            case DS_VALUE_INT64: {
                char buf[64]; snprintf(buf, 64, "%lld", (long long)box->as.i64); return ds_strdup(buf);
            }
            case DS_VALUE_BOOL: return (void*)(box->as.boolean ? DS_STR_TRUE_VAL : DS_STR_FALSE_VAL);
            case DS_VALUE_FLOAT: {
                char buf[64]; snprintf(buf, 64, "%g", box->as.f64); return ds_strdup(buf);
            }
            case DS_VALUE_STRUCT: return ds_strdup("{Struct}");
            case DS_VALUE_ARRAY: {
                DSArray *arr = (DSArray *)box->as.ptr;
                if (arr->length == 0) return ds_strdup("[]");
                
                char *buffer = (char *)ds_alloc(1024 * 16); 
                strcpy(buffer, "[");
                for (int64_t i = 0; i < arr->length; ++i) {
                    void *str_ptr = dragonstone_runtime_value_display(arr->items[i]);
                    strcat(buffer, (char *)str_ptr);
                    if (i < arr->length - 1) strcat(buffer, ", ");
                }
                strcat(buffer, "]");
                return buffer;
            }
        }
    }

    char *str = (char *)value;

    if (quote_strings) {
        size_t len = strlen(str);
        char *quoted = (char *)ds_alloc(len + 3); // "" + \0
        quoted[0] = '"';
        strcpy(quoted + 1, str);
        quoted[len + 1] = '"';
        quoted[len + 2] = '\0';
        return quoted;
    }

    return ds_strdup(str);
}

void *dragonstone_runtime_value_display(void *value) {
    return ds_format_value(value, true);
}

void *dragonstone_runtime_to_string(void *value) {
    return ds_format_value(value, false);
}

void *dragonstone_runtime_box_i32(int32_t v) { DSValue *b = ds_new_box(DS_VALUE_INT32); b->as.i32 = v; return b; }
void *dragonstone_runtime_box_i64(int64_t v) { DSValue *b = ds_new_box(DS_VALUE_INT64); b->as.i64 = v; return b; }
void *dragonstone_runtime_box_bool(int32_t v) { DSValue *b = ds_new_box(DS_VALUE_BOOL); b->as.boolean = v; return b; }
void *dragonstone_runtime_box_float(double v) { DSValue *b = ds_new_box(DS_VALUE_FLOAT); b->as.f64 = v; return b; }
void *dragonstone_runtime_box_string(void *v) { return v; }

void* dragonstone_runtime_box_struct(void* data, int64_t size) {
    DSValue* box = ds_new_box(DS_VALUE_STRUCT);
    void* heap_copy = ds_alloc((size_t)size);
    memcpy(heap_copy, data, (size_t)size);
    box->as.ptr = heap_copy;
    return box;
}

void* dragonstone_runtime_unbox_struct(void* value) {
    if (!value || !ds_is_boxed(value)) return NULL;
    DSValue* box = (DSValue*)value;
    if (box->kind != DS_VALUE_STRUCT) return NULL;
    return box->as.ptr;
}

int32_t dragonstone_runtime_unbox_i32(void *v) { if(ds_is_boxed(v) && ((DSValue*)v)->kind == DS_VALUE_INT32) return ((DSValue*)v)->as.i32; return 0; }
int64_t dragonstone_runtime_unbox_i64(void *v) { if(ds_is_boxed(v) && ((DSValue*)v)->kind == DS_VALUE_INT64) return ((DSValue*)v)->as.i64; return 0; }
int32_t dragonstone_runtime_unbox_bool(void *v) { if(ds_is_boxed(v) && ((DSValue*)v)->kind == DS_VALUE_BOOL) return ((DSValue*)v)->as.boolean; return 0; }

double dragonstone_runtime_unbox_float(void *v) { if(ds_is_boxed(v) && ((DSValue*)v)->kind == DS_VALUE_FLOAT) return ((DSValue*)v)->as.f64; return 0.0; }

void *dragonstone_runtime_map_literal(int64_t l, void **k, void **v) { return NULL; }
void *dragonstone_runtime_tuple_literal(int64_t l, void **e) { return NULL; }
void *dragonstone_runtime_named_tuple_literal(int64_t l, void **k, void **v) { return NULL; }
void *dragonstone_runtime_block_literal(void *f, void *e) { return NULL; }
void *dragonstone_runtime_block_invoke(void *h, int64_t c, void **v) { return NULL; }
void **dragonstone_runtime_block_env_allocate(int64_t l) { return calloc(l, sizeof(void*)); }
void *dragonstone_runtime_constant_lookup(int64_t l, void **s) { return NULL; }
void dragonstone_runtime_rescue_placeholder(void) { abort(); }
void *dragonstone_runtime_define_constant(void *n, void *v) { return v; }
void dragonstone_runtime_yield_missing_block(void) { abort(); }
