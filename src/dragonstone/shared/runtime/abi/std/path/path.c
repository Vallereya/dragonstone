#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include "path.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

#ifdef _WIN32
#include <direct.h>
#define DS_MKDIR(path) _mkdir(path)
#define DS_GETCWD _getcwd
#undef PATH_MAX
#define PATH_MAX _MAX_PATH
#else
#include <unistd.h>
#include <sys/stat.h>
#define DS_MKDIR(path) mkdir(path, 0755)
#define DS_GETCWD getcwd
#endif

static char *ds_strdup(const char *input) {
    if (!input) {
        char *out = (char *)malloc(1);
        if (out) out[0] = '\0';
        return out;
    }
    size_t len = strlen(input);
    char *out = (char *)malloc(len + 1);
    if (!out) return NULL;
    memcpy(out, input, len);
    out[len] = '\0';
    return out;
}

static int ds_is_sep(char ch) {
    return ch == '/' || ch == '\\';
}

static int ds_is_drive_prefix(const char *path) {
    return path && isalpha((unsigned char)path[0]) && path[1] == ':';
}

static int ds_is_unc_prefix(const char *path) {
    return path && ds_is_sep(path[0]) && ds_is_sep(path[1]);
}

static char *ds_normalize(const char *path) {
    if (!path || !*path) return ds_strdup(".");

    const char *p = path;
    char drive_prefix[4] = {0};
    size_t prefix_len = 0;
    int has_drive = ds_is_drive_prefix(p);

    if (has_drive) {
        drive_prefix[0] = p[0];
        drive_prefix[1] = ':';
        drive_prefix[2] = '\0';
        p += 2;
    }

    int is_unc = !has_drive && ds_is_unc_prefix(path);
    int is_absolute = 0;

    if (is_unc) {
        is_absolute = 1;
        p = path + 2;
    } else if (ds_is_sep(*p)) {
        is_absolute = 1;
        while (ds_is_sep(*p)) p++;
    }

    if (has_drive && is_absolute) {
        drive_prefix[2] = '/';
        drive_prefix[3] = '\0';
        prefix_len = 3;
    } else if (has_drive) {
        prefix_len = 2;
    } else if (is_unc) {
        prefix_len = 2;
    } else if (is_absolute) {
        prefix_len = 1;
    }

    size_t seg_cap = 16;
    size_t seg_len = 0;
    char **segments = (char **)malloc(seg_cap * sizeof(char *));
    if (!segments) return NULL;

    while (*p) {
        while (ds_is_sep(*p)) p++;
        const char *start = p;
        while (*p && !ds_is_sep(*p)) p++;
        size_t len = (size_t)(p - start);
        if (len == 0) continue;

        if (len == 1 && start[0] == '.') {
            continue;
        }
        if (len == 2 && start[0] == '.' && start[1] == '.') {
            if (seg_len > 0 && strcmp(segments[seg_len - 1], "..") != 0) {
                free(segments[--seg_len]);
            } else if (!is_absolute) {
                segments[seg_len++] = ds_strdup("..");
            }
            continue;
        }

        if (seg_len >= seg_cap) {
            seg_cap *= 2;
            char **resized = (char **)realloc(segments, seg_cap * sizeof(char *));
            if (!resized) {
                for (size_t i = 0; i < seg_len; ++i) free(segments[i]);
                free(segments);
                return NULL;
            }
            segments = resized;
        }

        char *segment = (char *)malloc(len + 1);
        if (!segment) {
            for (size_t i = 0; i < seg_len; ++i) free(segments[i]);
            free(segments);
            return NULL;
        }
        memcpy(segment, start, len);
        segment[len] = '\0';
        segments[seg_len++] = segment;
    }

    size_t total = prefix_len;
    if (seg_len > 0) {
        if (prefix_len == 2 && is_absolute) {
            total += 1;
        } else if (prefix_len == 2 && !is_absolute) {
            total += 0;
        }
    }

    for (size_t i = 0; i < seg_len; ++i) {
        total += strlen(segments[i]) + 1;
    }

    if (total == 0) total = 1;

    char *out = (char *)malloc(total + 1);
    if (!out) {
        for (size_t i = 0; i < seg_len; ++i) free(segments[i]);
        free(segments);
        return NULL;
    }

    size_t offset = 0;
    if (has_drive) {
        memcpy(out + offset, drive_prefix, prefix_len);
        offset += prefix_len;
    } else if (is_unc) {
        out[offset++] = '/';
        out[offset++] = '/';
    } else if (is_absolute) {
        out[offset++] = '/';
    }

    for (size_t i = 0; i < seg_len; ++i) {
        if (offset > 0 && out[offset - 1] != '/') {
            out[offset++] = '/';
        }
        size_t len = strlen(segments[i]);
        memcpy(out + offset, segments[i], len);
        offset += len;
    }

    if (offset == 0) {
        out[offset++] = '.';
    }

    out[offset] = '\0';

    for (size_t i = 0; i < seg_len; ++i) free(segments[i]);
    free(segments);

    return out;
}

static int ds_mkdirs(const char *path) {
    if (!path || !*path) return 0;
    char *normalized = ds_normalize(path);
    if (!normalized) return 0;

    char *cursor = normalized;
    if (ds_is_drive_prefix(cursor)) {
        cursor += 2;
        if (*cursor == '/') cursor++;
    } else if (ds_is_unc_prefix(cursor)) {
        cursor += 2;
    } else if (*cursor == '/') {
        cursor++;
    }

    for (; *cursor; ++cursor) {
        if (*cursor == '/') {
            *cursor = '\0';
            if (normalized[0] != '\0') {
                DS_MKDIR(normalized);
            }
            *cursor = '/';
        }
    }

    DS_MKDIR(normalized);
    free(normalized);
    return 1;
}

char *dragonstone_path_normalize(const char *path) {
    return ds_normalize(path);
}

char *dragonstone_path_expand(const char *path) {
    if (!path) return ds_strdup("");
    char cwd[PATH_MAX];
    if (!DS_GETCWD(cwd, sizeof(cwd))) {
        return ds_normalize(path);
    }

    int absolute = ds_is_drive_prefix(path) || ds_is_unc_prefix(path) || ds_is_sep(path[0]);
    if (absolute) {
        return ds_normalize(path);
    }

    size_t cwd_len = strlen(cwd);
    size_t path_len = strlen(path);
    size_t total = cwd_len + 1 + path_len;
    char *combined = (char *)malloc(total + 1);
    if (!combined) return NULL;
    memcpy(combined, cwd, cwd_len);
    combined[cwd_len] = '/';
    memcpy(combined + cwd_len + 1, path, path_len);
    combined[total] = '\0';

    char *normalized = ds_normalize(combined);
    free(combined);
    return normalized;
}

char *dragonstone_path_parent(const char *path) {
    char *normalized = ds_normalize(path);
    if (!normalized) return NULL;

    size_t len = strlen(normalized);
    if (len == 0 || strcmp(normalized, ".") == 0 || strcmp(normalized, "/") == 0) {
        free(normalized);
        return ds_strdup(".");
    }

    if (len == 3 && ds_is_drive_prefix(normalized) && normalized[2] == '/') {
        free(normalized);
        return ds_strdup(".");
    }

    while (len > 0 && normalized[len - 1] == '/') len--;
    while (len > 0 && normalized[len - 1] != '/') len--;

    if (len == 0) {
        free(normalized);
        return ds_strdup(".");
    }

    if (ds_is_drive_prefix(normalized) && len == 3 && normalized[2] == '/') {
        normalized[3] = '\0';
        return normalized;
    }

    if (len == 2 && ds_is_drive_prefix(normalized)) {
        normalized[len] = '\0';
        return normalized;
    }

    normalized[len - 1] = '\0';
    if (normalized[0] == '\0') {
        free(normalized);
        return ds_strdup(".");
    }

    return normalized;
}

char *dragonstone_path_base(const char *path) {
    char *normalized = ds_normalize(path);
    if (!normalized) return NULL;

    size_t len = strlen(normalized);
    while (len > 0 && normalized[len - 1] == '/') len--;
    if (len == 0) {
        free(normalized);
        return ds_strdup(".");
    }

    size_t start = len;
    while (start > 0 && normalized[start - 1] != '/') start--;
    char *out = ds_strdup(normalized + start);
    free(normalized);
    return out;
}

char *dragonstone_path_delete(const char *path) {
    char *parent = dragonstone_path_parent(path);
    if (!parent) return NULL;

    if (strcmp(parent, ".") == 0) {
        free(parent);
        return ds_strdup("./");
    }

    if (strcmp(parent, "./") == 0) {
        return parent;
    }

    return parent;
}

char *dragonstone_path_create(const char *path) {
    if (!path) return ds_strdup("");
    ds_mkdirs(path);
    return dragonstone_path_expand(path);
}
