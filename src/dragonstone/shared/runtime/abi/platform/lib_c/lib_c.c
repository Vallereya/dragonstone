#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include "lib_c.h"

DSPlatformFile *ds_platform_stdin(void) {
    return stdin;
}

DSPlatformFile *ds_platform_stdout(void) {
    return stdout;
}

DSPlatformFile *ds_platform_stderr(void) {
    return stderr;
}

size_t ds_platform_fwrite(const void *ptr, size_t size, size_t nmemb, DSPlatformFile *stream) {
    return fwrite(ptr, size, nmemb, stream);
}

char *ds_platform_fgets(char *str, int size, DSPlatformFile *stream) {
    return fgets(str, size, stream);
}

int ds_platform_fgetc(DSPlatformFile *stream) {
    return fgetc(stream);
}

int ds_platform_fputc(int ch, DSPlatformFile *stream) {
    return fputc(ch, stream);
}

int ds_platform_fflush(DSPlatformFile *stream) {
    return fflush(stream);
}

DSPlatformFile *ds_platform_fopen(const char *path, const char *mode) {
    return fopen(path, mode);
}

int ds_platform_fclose(DSPlatformFile *stream) {
    return fclose(stream);
}

int ds_platform_fseek(DSPlatformFile *stream, long offset, int origin) {
    return fseek(stream, offset, origin);
}

long ds_platform_ftell(DSPlatformFile *stream) {
    return ftell(stream);
}

size_t ds_platform_fread(void *ptr, size_t size, size_t nmemb, DSPlatformFile *stream) {
    return fread(ptr, size, nmemb, stream);
}
