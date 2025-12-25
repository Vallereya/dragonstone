// Provides native I/O functions for Dragonstone runtime,
// independent of host I/O.

#include <stdlib.h>
#include <string.h>
#include "../../platform/platform.h"
#include "io.h"

static int64_t ds_program_argc = 0;
static char **ds_program_argv = NULL;

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

static char *ds_read_line(DSPlatformFile *fp) {
    if (!fp) return ds_strdup("");
    char buf[4096];
    if (!ds_platform_fgets(buf, (int)sizeof(buf), fp)) return ds_strdup("");
    size_t len = strlen(buf);
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r')) len--;
    char *out = (char *)malloc(len + 1);
    if (!out) return NULL;
    memcpy(out, buf, len);
    out[len] = '\0';
    return out;
}

static char *ds_read_to_end(DSPlatformFile *fp) {
    if (!fp) return ds_strdup("");
    size_t cap = 4096;
    size_t len = 0;
    char *out = (char *)malloc(cap);
    if (!out) return NULL;
    int ch;
    while ((ch = ds_platform_fgetc(fp)) != EOF) {
        if (len + 1 >= cap) {
            cap *= 2;
            char *resized = (char *)realloc(out, cap);
            if (!resized) {
                free(out);
                return NULL;
            }
            out = resized;
        }
        out[len++] = (char)ch;
    }
    out[len] = '\0';
    return out;
}

void dragonstone_io_set_argv(int64_t argc, char **argv) {
    ds_program_argc = argc;
    ds_program_argv = argv;
}

int64_t dragonstone_io_argc(void) {
    if (ds_program_argc > 1 && ds_program_argv) {
        return ds_program_argc - 1;
    }
    return 0;
}

const char **dragonstone_io_argv(void) {
    if (ds_program_argc > 1 && ds_program_argv) {
        return (const char **)(ds_program_argv + 1);
    }
    return NULL;
}

void dragonstone_io_write_stdout(const uint8_t *bytes, size_t len) {
    ds_platform_fwrite(bytes, 1, len, ds_platform_stdout());
}

void dragonstone_io_write_stderr(const uint8_t *bytes, size_t len) {
    ds_platform_fwrite(bytes, 1, len, ds_platform_stderr());
}

void dragonstone_io_flush_stdout(void) {
    ds_platform_fflush(ds_platform_stdout());
}

void dragonstone_io_flush_stderr(void) {
    ds_platform_fflush(ds_platform_stderr());
}

char *dragonstone_io_read_stdin_line(void) {
    return ds_read_line(ds_platform_stdin());
}

char *dragonstone_io_read_argf(void) {
    if (!(ds_program_argc > 1 && ds_program_argv)) {
        return ds_read_to_end(ds_platform_stdin());
    }

    size_t cap = 4096;
    size_t len = 0;
    char *out = (char *)malloc(cap);
    if (!out) return NULL;
    out[0] = '\0';

    for (int64_t i = 1; i < ds_program_argc; ++i) {
        const char *path = ds_program_argv[i];
        if (!path) continue;
        DSPlatformFile *fp = ds_platform_fopen(path, "rb");
        if (!fp) continue;
        ds_platform_fseek(fp, 0, SEEK_END);
        long fsize = ds_platform_ftell(fp);
        ds_platform_fseek(fp, 0, SEEK_SET);
        if (fsize > 0) {
            size_t need = (size_t)fsize;
            if (len + need + 1 >= cap) {
                while (len + need + 1 >= cap) cap *= 2;
                char *resized = (char *)realloc(out, cap);
                if (!resized) {
                    ds_platform_fclose(fp);
                    free(out);
                    return NULL;
                }
                out = resized;
            }
            size_t got = ds_platform_fread(out + len, 1, need, fp);
            len += got;
            out[len] = '\0';
        }
        ds_platform_fclose(fp);
    }

    return out;
}
