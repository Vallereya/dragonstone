#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* 
    Returns a heap copy of the env variable's value, 
    or null when the variable is not set. The caller 
    owns the result and frees it with
    `dragonstone_std_free`.

    null means "not set" and an empty string means 
    "set to the empty string". 
*/
char *dragonstone_env_get(const char *key);

#ifdef __cplusplus
}
#endif
