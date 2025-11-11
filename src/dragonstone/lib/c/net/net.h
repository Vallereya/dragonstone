// WORK IN PROGRESS
// #pragma once
// #include <stddef.h>
// #include <stdint.h>

// #if defined(_WIN32)
//     #define NET_API __declspec(dllexport)
// #else
//     #define NET_API __attribute__((visibility("default")))
// #endif

// #ifdef __cplusplus
// extern "C" {
// #endif

// // Initialize/Cleanup (WinSock needs this).
// // Call init once at process start.
// NET_API int  net_init(void);
// NET_API void net_cleanup(void);

// // Errors (per-thread). Query immediately after any failure.
// NET_API int  last_error_code(void);
// NET_API int  last_error_message(char* buf, size_t buflen);

// // TCP: Helpers (this is blocking by default).
// NET_API int  tcp_listen(const char* host, uint16_t port, int backlog);                          // returns fd or -1
// NET_API int  tcp_accept(int server_fd, char* ipbuf, size_t ipbuflen, uint16_t* out_port);       // returns client fd or -1
// NET_API int  tcp_connect(const char* host, uint16_t port, int timeout_ms);                      // timeout_ms <= 0 -> block

// // I/O
// NET_API int  set_nonblocking(int fd, int enable);                                               // 0 OK, -1 err
// NET_API int  send(int fd, const void* data, int len);                                           // returns bytes or -1
// NET_API int  recv(int fd, void* data, int len);                                                 // returns bytes or -1
// NET_API int  close(int fd);                                                                     // 0 OK, -1 err

// // A simple poll for now (readable=1, writable=2).
// // returns: #ready, 0 timeout, -1 error
// typedef struct {
//   int fd;
//   short events;                                                                                 // bitmask: 1=read, 2=write
//   short revents;                                                                                // out
// } pollfd;

// NET_API int poll(pollfd* fds, int nfds, int timeout_ms);

// #ifdef __cplusplus
// }
// #endif
