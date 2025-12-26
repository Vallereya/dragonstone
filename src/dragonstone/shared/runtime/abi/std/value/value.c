#ifndef VALUE_H
#define VALUE_H

#include <stdint.h>
#include <stdbool.h>

// Boxing and tagged unions is simpler to start.
typedef enum {
    dragonstone_VAL_NIL,
    dragonstone_VAL_BOOL,
    dragonstone_VAL_INT,
    dragonstone_VAL_FLOAT,
    dragonstone_VAL_STRING,
    dragonstone_VAL_ARRAY,
    dragonstone_VAL_MAP,
    dragonstone_VAL_OBJECT,
    dragonstone_VAL_FUNCTION,
    dragonstone_VAL_CHANNEL,
} DsValueType;

typedef struct DsValue {
    DsValueType type;
    union {
        bool boolean;
        int64_t integer;
        double floating;
        struct DsString* string;
        struct DsArray* array;
        struct DsMap* map;
        struct DsObject* object;
        struct DsFunction* function;
        struct DsChannel* channel;
    } as;
} DsValue;

// Constructors.
DsValue dragonstone_nil(void);
DsValue dragonstone_bool(bool value);
DsValue dragonstone_int(int64_t value);
DsValue dragonstone_float(double value);
DsValue dragonstone_string(const char* chars, size_t length);

// Type checks.
bool dragonstone_is_nil(DsValue value);
bool dragonstone_is_truthy(DsValue value);

#endif