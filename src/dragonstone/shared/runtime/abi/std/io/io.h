#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void dragonstone_io_set_argv(int64_t argc, char **argv);
int64_t dragonstone_io_argc(void);
const char **dragonstone_io_argv(void);

void dragonstone_io_write_stdout(const uint8_t *bytes, size_t len);
void dragonstone_io_write_stderr(const uint8_t *bytes, size_t len);
void dragonstone_io_flush_stdout(void);
void dragonstone_io_flush_stderr(void);

char *dragonstone_io_read_stdin_line(void);
char *dragonstone_io_read_argf(void);

#ifdef __cplusplus
}
#endif
