#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int dragonstone_file_exists(const char *path);
int dragonstone_file_is_file(const char *path);
int64_t dragonstone_file_size(const char *path);

char *dragonstone_file_read(const char *path);
int64_t dragonstone_file_write(const char *path, const uint8_t *bytes, size_t len, int append);
int dragonstone_file_delete(const char *path);

#ifdef __cplusplus
}
#endif
