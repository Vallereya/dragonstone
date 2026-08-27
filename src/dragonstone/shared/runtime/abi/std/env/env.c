#define _CRT_SECURE_NO_WARNINGS
#include <stdlib.h>
#include <string.h>
#include "env.h"

/*
    Local rather than shared with `path.c`'s `ds_strdup`; 
    one answers "" for a null input.
*/
static char *ds_env_dup(const char *input)
{
    size_t len = strlen(input);
    char *out = (char *)malloc(len + 1);

    if (!out) return NULL;

    memcpy(out, input, len);
    out[len] = '\0';
    return out;
}

/* 
    An allocation failure also answers null, and the caller 
    reads that as "not set". Left that way on purpose
    because the alternative is a second entry point nothing 
    would use.
*/
char *dragonstone_env_get(const char *key)
{
    const char *value;

    if (!key || !*key) return NULL;

    value = getenv(key);
    if (!value) return NULL;

    return ds_env_dup(value);
}
