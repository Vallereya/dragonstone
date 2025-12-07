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
    DS_VALUE_FLOAT
} DSValueKind;

typedef struct {
    uint32_t magic;
    DSValueKind kind;
    union {
        int32_t i32;
        int64_t i64;
        bool boolean;
        double f64;
    } as;
} DSValue;

typedef struct {
    int64_t length;
    void **items;
} DSArray;

typedef struct {
    int64_t length;
    void **keys;
    void **values;
} DSMap;

typedef struct {
    void *function;
    void *environment;
} DSBlockHandle;

typedef struct {
    char *name;
    void *value;
} DSConstantEntry;

typedef struct DSClass DSClass;

struct DSClass {
    const char *name;
    DSClass *parent;
    void **vtable;
    size_t vtable_size;
    size_t instance_size;
};

typedef struct {
    DSClass *klass;
} DSObject;

static DSConstantEntry *g_constant_table = NULL;
static size_t g_constant_count = 0;
static size_t g_constant_capacity = 0;
static const char DS_STR_NIL[] = "nil";
static const char DS_STR_TRUE[] = "true";
static const char DS_STR_FALSE[] = "false";

static void runtime_stub_log(const char *fn_name) {
    fprintf(stderr, "[dragonstone][runtime] %s invoked.\n", fn_name);
}

static void runtime_stub_hit(const char *fn_name) {
    runtime_stub_log(fn_name);
}

static NORETURN void runtime_stub_fatal(const char *fn_name, const char *message) {
    fprintf(stderr, "[dragonstone][runtime] %s failed: %s\n", fn_name, message);
    abort();
}

static void *ds_alloc(size_t size) {
    void *buffer = calloc(1, size);
    if (!buffer) {
        runtime_stub_fatal("ds_alloc", "out of memory");
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
    if (!value) {
        return false;
    }
    DSValue *box = (DSValue *)value;
    return box->magic == DS_BOX_MAGIC;
}

static bool ds_unbox_int(void *value, int64_t *out) {
    if (!value || !out) {
        return false;
    }
    if (!ds_is_boxed(value)) {
        return false;
    }
    DSValue *box = (DSValue *)value;
    switch (box->kind) {
        case DS_VALUE_INT32:
            *out = (int64_t)box->as.i32;
            return true;
        case DS_VALUE_INT64:
            *out = box->as.i64;
            return true;
        default:
            return false;
    }
}

static bool ds_unbox_bool(void *value, bool *out) {
    if (!value || !out) {
        return false;
    }
    if (!ds_is_boxed(value)) {
        return false;
    }
    DSValue *box = (DSValue *)value;
    if (box->kind != DS_VALUE_BOOL) {
        return false;
    }
    *out = box->as.boolean;
    return true;
}

static DSArray *ds_new_array(int64_t length, void **elements) {
    DSArray *array = (DSArray *)ds_alloc(sizeof(DSArray));
    array->length = length;
    if (length > 0) {
        array->items = (void **)ds_alloc(sizeof(void *) * (size_t)length);
        for (int64_t i = 0; i < length; ++i) {
            array->items[i] = elements ? elements[i] : NULL;
        }
    } else {
        array->items = NULL;
    }
    return array;
}

static DSMap *ds_new_map(int64_t length, void **keys, void **values) {
    DSMap *map = (DSMap *)ds_alloc(sizeof(DSMap));
    map->length = length;
    if (length > 0) {
        map->keys = (void **)ds_alloc(sizeof(void *) * (size_t)length);
        map->values = (void **)ds_alloc(sizeof(void *) * (size_t)length);
        for (int64_t i = 0; i < length; ++i) {
            map->keys[i] = keys ? keys[i] : NULL;
            map->values[i] = values ? values[i] : NULL;
        }
    } else {
        map->keys = NULL;
        map->values = NULL;
    }
    return map;
}

static void ds_constants_grow(void) {
    size_t new_capacity = g_constant_capacity == 0 ? 8 : g_constant_capacity * 2;
    DSConstantEntry *entries = (DSConstantEntry *)realloc(g_constant_table, new_capacity * sizeof(DSConstantEntry));
    if (!entries) {
        runtime_stub_fatal("dragonstone_runtime_define_constant", "constant table allocation failed");
    }
    g_constant_table = entries;
    for (size_t i = g_constant_capacity; i < new_capacity; ++i) {
        g_constant_table[i].name = NULL;
        g_constant_table[i].value = NULL;
    }
    g_constant_capacity = new_capacity;
}

static char *ds_strdup(const char *input) {
    if (!input) {
        return NULL;
    }
    size_t len = strlen(input);
    char *copy = (char *)ds_alloc(len + 1);
    memcpy(copy, input, len + 1);
    return copy;
}

static char *ds_join_segments(int64_t length, void **segments) {
    if (length <= 0) {
        return NULL;
    }
    size_t total = 0;
    for (int64_t i = 0; i < length; ++i) {
        const char *segment = segments ? (const char *)segments[i] : "";
        if (segment) {
            total += strlen(segment);
        }
        if (i + 1 < length) {
            total += 2; // "::"
        }
    }
    char *buffer = (char *)ds_alloc(total + 1);
    buffer[0] = '\0';
    for (int64_t i = 0; i < length; ++i) {
        const char *segment = segments ? (const char *)segments[i] : "";
        if (segment) {
            strcat(buffer, segment);
        }
        if (i + 1 < length) {
            strcat(buffer, "::");
        }
    }
    return buffer;
}

void *dragonstone_runtime_box_i32(int32_t value) {
    DSValue *box = ds_new_box(DS_VALUE_INT32);
    box->as.i32 = value;
    return box;
}

void *dragonstone_runtime_box_i64(int64_t value) {
    DSValue *box = ds_new_box(DS_VALUE_INT64);
    box->as.i64 = value;
    return box;
}

void *dragonstone_runtime_box_bool(int32_t value) {
    DSValue *box = ds_new_box(DS_VALUE_BOOL);
    box->as.boolean = value != 0;
    return box;
}

void *dragonstone_runtime_box_float(double value) {
    DSValue *box = ds_new_box(DS_VALUE_FLOAT);
    box->as.f64 = value;
    return box;
}

void *dragonstone_runtime_box_string(void *value) {
    return value;
}

void *dragonstone_runtime_array_literal(int64_t length, void **elements) {
    return ds_new_array(length, elements);
}

void *dragonstone_runtime_map_literal(int64_t length, void **keys, void **values) {
    return ds_new_map(length, keys, values);
}

void *dragonstone_runtime_tuple_literal(int64_t length, void **elements) {
    return ds_new_array(length, elements);
}

void *dragonstone_runtime_named_tuple_literal(int64_t length, void **keys, void **values) {
    return ds_new_map(length, keys, values);
}

void *dragonstone_runtime_block_literal(void *fn_ptr, void *env_ptr) {
    if (!fn_ptr) {
        return NULL;
    }
    DSBlockHandle *handle = (DSBlockHandle *)ds_alloc(sizeof(DSBlockHandle));
    handle->function = fn_ptr;
    handle->environment = env_ptr;
    return handle;
}

void *dragonstone_runtime_block_invoke(void *block_handle, int64_t argc, void **argv) {
    if (!block_handle) {
        runtime_stub_fatal("dragonstone_runtime_block_invoke", "null block handle");
    }
    DSBlockHandle *handle = (DSBlockHandle *)block_handle;
    if (!handle->function) {
        runtime_stub_fatal("dragonstone_runtime_block_invoke", "missing function pointer");
    }
    if (argc < 0) {
        runtime_stub_fatal("dragonstone_runtime_block_invoke", "negative argument count");
    }
    if (argc > 0 && !argv) {
        runtime_stub_fatal("dragonstone_runtime_block_invoke", "argument buffer missing");
    }
    typedef void *(*BlockFn)(void *, int64_t, void **);
    BlockFn fn = (BlockFn)handle->function;
    return fn(handle->environment, argc, argv);
}

void *dragonstone_runtime_alloc_instance(void *class_handle, int64_t field_bytes) {
    if (!class_handle) {
        runtime_stub_fatal("dragonstone_runtime_alloc_instance", "class pointer missing");
    }
    if (field_bytes < 0) {
        runtime_stub_fatal("dragonstone_runtime_alloc_instance", "negative field size");
    }
    size_t payload = (size_t)field_bytes;
    size_t total = sizeof(DSObject) + payload;
    DSObject *object = (DSObject *)ds_alloc(total);
    object->klass = (DSClass *)class_handle;
    return object;
}

void *dragonstone_runtime_method_invoke(void *receiver, void *method_name, int64_t argc, void **argv) {
    (void)receiver;
    (void)method_name;
    (void)argc;
    (void)argv;
    runtime_stub_hit(__func__);
    return NULL;
}

void **dragonstone_runtime_block_env_allocate(int64_t length) {
    if (length <= 0) {
        return NULL;
    }
    size_t count = (size_t)length;
    void **buffer = (void **)ds_alloc(sizeof(void *) * count);
    return buffer;
}

void *dragonstone_runtime_constant_lookup(int64_t length, void **segments) {
    char *name = ds_join_segments(length, segments);
    if (!name) {
        return NULL;
    }
    for (size_t i = 0; i < g_constant_count; ++i) {
        if (g_constant_table[i].name && strcmp(g_constant_table[i].name, name) == 0) {
            free(name);
            return g_constant_table[i].value;
        }
    }
    free(name);
    return NULL;
}

void dragonstone_runtime_rescue_placeholder(void) {
    runtime_stub_fatal("dragonstone_runtime_rescue_placeholder", "rescue clauses are not implemented");
}

void *dragonstone_runtime_define_constant(void *name_ptr, void *value) {
    const char *name = (const char *)name_ptr;
    if (!name || !*name) {
        runtime_stub_fatal("dragonstone_runtime_define_constant", "constant name is missing");
    }
    for (size_t i = 0; i < g_constant_count; ++i) {
        if (g_constant_table[i].name && strcmp(g_constant_table[i].name, name) == 0) {
            g_constant_table[i].value = value;
            return value;
        }
    }
    if (g_constant_count == g_constant_capacity) {
        ds_constants_grow();
    }
    g_constant_table[g_constant_count].name = ds_strdup(name);
    g_constant_table[g_constant_count].value = value;
    ++g_constant_count;
    return value;
}

void *dragonstone_runtime_index_get(void *object, void *index_value) {
    if (!object) {
        return NULL;
    }
    DSArray *array = (DSArray *)object;
    int64_t index = 0;
    if (!ds_unbox_int(index_value, &index)) {
        runtime_stub_log("dragonstone_runtime_index_get");
        return NULL;
    }
    if (index < 0 || index >= array->length) {
        return NULL;
    }
    return array->items ? array->items[index] : NULL;
}

void *dragonstone_runtime_index_set(void *object, void *index_value, void *value) {
    if (!object) {
        return NULL;
    }
    DSArray *array = (DSArray *)object;
    int64_t index = 0;
    if (!ds_unbox_int(index_value, &index)) {
        runtime_stub_log("dragonstone_runtime_index_set");
        return NULL;
    }
    if (index < 0 || index >= array->length) {
        return NULL;
    }
    if (array->items) {
        array->items[index] = value;
    }
    return value;
}

int32_t dragonstone_runtime_unbox_i32(void *value) {
    int64_t result = 0;
    if (!ds_unbox_int(value, &result)) {
        runtime_stub_log(__func__);
        return 0;
    }
    return (int32_t)result;
}

int64_t dragonstone_runtime_unbox_i64(void *value) {
    int64_t result = 0;
    if (!ds_unbox_int(value, &result)) {
        runtime_stub_log(__func__);
        return 0;
    }
    return result;
}

int32_t dragonstone_runtime_unbox_bool(void *value) {
    bool result = false;
    if (!ds_unbox_bool(value, &result)) {
        runtime_stub_log(__func__);
        return 0;
    }
    return result ? 1 : 0;
}

double dragonstone_runtime_unbox_float(void *value) {
    if (!value) {
        runtime_stub_log(__func__);
        return 0.0;
    }
    if (!ds_is_boxed(value)) {
        runtime_stub_log(__func__);
        return 0.0;
    }
    DSValue *box = (DSValue *)value;
    switch (box->kind) {
        case DS_VALUE_FLOAT:
            return box->as.f64;
        case DS_VALUE_INT64:
            return (double)box->as.i64;
        case DS_VALUE_INT32:
            return (double)box->as.i32;
        case DS_VALUE_BOOL:
            return box->as.boolean ? 1.0 : 0.0;
        default:
            runtime_stub_log(__func__);
            return 0.0;
    }
}

void *dragonstone_runtime_value_display(void *value) {
    if (!value) {
        return (void *)DS_STR_NIL;
    }
    if (!ds_is_boxed(value)) {
        return value;
    }

    DSValue *box = (DSValue *)value;
    switch (box->kind) {
        case DS_VALUE_BOOL:
            return (void *)(box->as.boolean ? DS_STR_TRUE : DS_STR_FALSE);
        case DS_VALUE_INT32: {
            char buffer[32];
            snprintf(buffer, sizeof(buffer), "%d", box->as.i32);
            return ds_strdup(buffer);
        }
        case DS_VALUE_INT64: {
            char buffer[64];
            snprintf(buffer, sizeof(buffer), "%lld", (long long)box->as.i64);
            return ds_strdup(buffer);
        }
        case DS_VALUE_FLOAT: {
            char buffer[64];
            snprintf(buffer, sizeof(buffer), "%g", box->as.f64);
            return ds_strdup(buffer);
        }
        default:
            return (void *)DS_STR_NIL;
    }
}

static bool ds_compare_strings(const char *lhs, const char *rhs) {
    if (!lhs || !rhs) {
        return false;
    }
    return strcmp(lhs, rhs) == 0;
}

_Bool dragonstone_runtime_case_compare(void *lhs, void *rhs) {
    if (lhs == rhs) {
        return true;
    }
    if (!lhs || !rhs) {
        return false;
    }
    if (ds_is_boxed(lhs) && ds_is_boxed(rhs)) {
        DSValue *left = (DSValue *)lhs;
        DSValue *right = (DSValue *)rhs;
        if (left->kind != right->kind) {
            return false;
        }
        switch (left->kind) {
            case DS_VALUE_INT32:
                return left->as.i32 == right->as.i32;
            case DS_VALUE_INT64:
                return left->as.i64 == right->as.i64;
            case DS_VALUE_FLOAT:
                return left->as.f64 == right->as.f64;
            case DS_VALUE_BOOL:
                return left->as.boolean == right->as.boolean;
            default:
                return false;
        }
    }
    const char *left_str = (const char *)lhs;
    const char *right_str = (const char *)rhs;
    return ds_compare_strings(left_str, right_str);
}

void dragonstone_runtime_yield_missing_block(void) {
    runtime_stub_fatal("dragonstone_runtime_yield_missing_block", "missing block for yield");
}
