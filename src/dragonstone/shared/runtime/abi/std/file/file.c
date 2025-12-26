#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include "file.h"

#ifdef _WIN32
#include <io.h>
#include <direct.h>
#define DS_STAT _stat
#define DS_STAT_STRUCT struct _stat
#define DS_UNLINK _unlink
#define DS_RMDIR _rmdir
#else
#include <unistd.h>
#define DS_STAT stat
#define DS_STAT_STRUCT struct stat
#define DS_UNLINK unlink
#define DS_RMDIR rmdir
#endif

int dragonstone_file_exists(const char *path) {
    DS_STAT_STRUCT st;
    return path && DS_STAT(path, &st) == 0;
}

int dragonstone_file_is_file(const char *path) {
    DS_STAT_STRUCT st;
    if (!path || DS_STAT(path, &st) != 0) return 0;
#ifdef _WIN32
    return (st.st_mode & _S_IFREG) != 0;
#else
    return S_ISREG(st.st_mode);
#endif
}

int64_t dragonstone_file_size(const char *path) {
    DS_STAT_STRUCT st;
    if (!path || DS_STAT(path, &st) != 0) return -1;
    return (int64_t)st.st_size;
}

char *dragonstone_file_read(const char *path) {
    if (!path) return NULL;
    FILE *fp = fopen(path, "rb");
    if (!fp) return NULL;
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return NULL;
    }
    long fsize = ftell(fp);
    if (fsize < 0) {
        fclose(fp);
        return NULL;
    }
    rewind(fp);
    size_t size = (size_t)fsize;
    char *buf = (char *)malloc(size + 1);
    if (!buf) {
        fclose(fp);
        return NULL;
    }
    size_t read = fread(buf, 1, size, fp);
    buf[read] = '\0';
    fclose(fp);
    return buf;
}

int64_t dragonstone_file_write(const char *path, const uint8_t *bytes, size_t len, int append) {
    if (!path) return -1;
    const char *mode = append ? "ab" : "wb";
    FILE *fp = fopen(path, mode);
    if (!fp) return -1;
    size_t written = 0;
    if (bytes && len > 0) {
        written = fwrite(bytes, 1, len, fp);
    }
    fclose(fp);
    return (int64_t)written;
}

int dragonstone_file_delete(const char *path) {
    if (!path) return 0;
    if (DS_UNLINK(path) == 0) return 1;
    if (DS_RMDIR(path) == 0) return 1;
    return 0;
}
