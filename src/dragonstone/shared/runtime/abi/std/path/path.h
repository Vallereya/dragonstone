#pragma once

#ifdef __cplusplus
extern "C" {
#endif

char *dragonstone_path_create(const char *path);
char *dragonstone_path_normalize(const char *path);
char *dragonstone_path_parent(const char *path);
char *dragonstone_path_base(const char *path);
char *dragonstone_path_expand(const char *path);
char *dragonstone_path_delete(const char *path);

#ifdef __cplusplus
}
#endif
