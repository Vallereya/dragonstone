#pragma once

#include <stdio.h>
#include <stdint.h>
#include <stddef.h>

typedef FILE DSPlatformFile;

DSPlatformFile *ds_platform_stdin(void);
DSPlatformFile *ds_platform_stdout(void);
DSPlatformFile *ds_platform_stderr(void);

size_t ds_platform_fwrite(const void *ptr, size_t size, size_t nmemb, DSPlatformFile *stream);
char *ds_platform_fgets(char *str, int size, DSPlatformFile *stream);
int ds_platform_fgetc(DSPlatformFile *stream);
int ds_platform_fputc(int ch, DSPlatformFile *stream);
int ds_platform_fflush(DSPlatformFile *stream);

DSPlatformFile *ds_platform_fopen(const char *path, const char *mode);
int ds_platform_fclose(DSPlatformFile *stream);
int ds_platform_fseek(DSPlatformFile *stream, long offset, int origin);
long ds_platform_ftell(DSPlatformFile *stream);
size_t ds_platform_fread(void *ptr, size_t size, size_t nmemb, DSPlatformFile *stream);
