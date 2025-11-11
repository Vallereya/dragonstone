// WORK IN PROGRESS
// #define _POSIX_C_SOURCE 200809L
// #include "net.h"
// #include <string.h>

// #if defined(_WIN32)
//     #include <winsock2.h>
//     #include <ws2tcpip.h>
//     #pragma comment(lib, "ws2_32.lib")
//     #define close closesocket

//     static __declspec(thread) int g_last_err = 0;

//     static void set_err_from_wsa(void){ 
//         g_last_err = WSAGetLastError(); 
//     }

//     static int  map_err(void){
//         return g_last_err; 
//     }
// #else
//     #include <unistd.h>
//     #include <errno.h>
//     #include <fcntl.h>
//     #include <netdb.h>
//     #include <sys/types.h>
//     #include <sys/socket.h>
//     #include <netinet/tcp.h>
//     #include <poll.h>


//     static __thread int g_last_err = 0;

//     static void set_err(int e){ 
//         g_last_err = e; 
//     }

//     static int  map_err(void){ 
//         return g_last_err; 
//     }
// #endif

// static void set_last_err_from_errno(void){
// #if defined(_WIN32)
//     set_err_from_wsa();
// #else
//     set_err(errno);
// #endif
// }

// int net_init(void){
// #if defined(_WIN32)
//     WSADATA wsa;
//     if (WSAStartup(MAKEWORD(2,2), &wsa) != 0) { 
//         set_err_from_wsa(); return -1; 
//     }
// #endif
//     return 0;
// }

// void net_cleanup(void){
// #if defined(_WIN32)
//     WSACleanup();
// #endif
// }

// int last_error_code(void){ 
//     return map_err(); 
// }

// int last_error_message(char* buf, size_t buflen){
//     if (!buf || buflen == 0) return 0;
// #if defined(_WIN32)
//     int code = g_last_err ? g_last_err : WSAGetLastError();
//     DWORD flags = FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
//     DWORD n = FormatMessageA(flags, NULL, code, 0, buf, (DWORD)buflen, NULL);

//     if (n == 0) { 
//         strncpy(buf, "Unknown WinSock error", buflen); buf[buflen-1] = 0; return (int)strlen(buf); 
//     }


//     // Trim trailing newlines for Windows.
//     while (n>0 && (buf[n-1]=='\r' || buf[n-1]=='\n')) buf[--n]=0;
//     return (int)n;
// #else
//     int code = g_last_err ? g_last_err : errno;
//     const char* msg = strerror(code);
//     strncpy(buf, msg, buflen);
//     buf[buflen-1] = 0;
//     return (int)strlen(buf);
// #endif
// }

// static int set_reuseaddr(int fd){
//     int yes = 1;

//     if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (const char*)&yes, sizeof(yes)) != 0) {
//         set_last_err_from_errno(); return -1;
//     }

//     return 0;
// }

// int set_nonblocking(int fd, int enable){
// #if defined(_WIN32)
//     u_long nb = enable ? 1 : 0;

//     if (ioctlsocket(fd, FIONBIO, &nb) != 0){ 
//         set_last_err_from_errno(); return -1; 
//     }

//     return 0;
// #else
//     int flags = fcntl(fd, F_GETFL, 0);

//     if (flags < 0){ 
//         set_last_err_from_errno(); return -1; 
//     }

//     if (enable) flags |= O_NONBLOCK; else flags &= ~O_NONBLOCK;

//     if (fcntl(fd, F_SETFL, flags) != 0){ 
//         set_last_err_from_errno(); return -1; 
//     }

//     return 0;
// #endif
// }

// int tcp_listen(const char* host, uint16_t port, int backlog){
//     char service[16];
//     snprintf(service, sizeof(service), "%u", (unsigned)port);

//     struct addrinfo hints; memset(&hints, 0, sizeof(hints));
//     hints.ai_family   = AF_UNSPEC;                                                              // v4 or v6
//     hints.ai_socktype = SOCK_STREAM;
//     hints.ai_flags    = AI_PASSIVE;                                                             // for bind
//     struct addrinfo* res = NULL;

//     if (getaddrinfo(host && host[0]?host:NULL, service, &hints, &res) != 0) {
//         set_last_err_from_errno(); return -1;
//     }

//     int fd = -1;

//     for (struct addrinfo* ai = res; ai; ai = ai->ai_next) {
//         int s = (int)socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);

//         if (s < 0) { 
//             set_last_err_from_errno(); continue; 
//         }

//         if (set_reuseaddr(s) != 0){ 
//             close(s); s = -1; continue; 
//         }

//         if (bind(s, ai->ai_addr, (int)ai->ai_addrlen) != 0) { 
//             set_last_err_from_errno(); close(s); s = -1; continue; 
//         }

//         if (listen(s, backlog < 0 ? 128 : backlog) != 0) { 
//             set_last_err_from_errno(); close(s); s = -1; continue; 
//         }

//         fd = s; break;
//     }

//     freeaddrinfo(res);
//     return fd;                                                                                  // -1 if none succeeded
// }

// int tcp_accept(int server_fd, char* ipbuf, size_t ipbuflen, uint16_t* out_port){
//     struct sockaddr_storage ss; socklen_t slen = sizeof(ss);
// #if defined(_WIN32)
//     int cfd = (int)accept(server_fd, (struct sockaddr*)&ss, &slen);
// #else
//     int cfd = (int)accept(server_fd, (struct sockaddr*)&ss, &slen);
// #endif
//     if (cfd < 0){ 
//         set_last_err_from_errno(); return -1; 
//     }

//     if (ipbuf && ipbuflen > 0) {
//         void* addr = NULL; uint16_t port = 0;
//         if (ss.ss_family == AF_INET) {
//             struct sockaddr_in* sa = (struct sockaddr_in*)&ss;
//             addr = &sa->sin_addr; port = ntohs(sa->sin_port);
//         } else if (ss.ss_family == AF_INET6) {
//             struct sockaddr_in6* sa6 = (struct sockaddr_in6*)&ss;
//             addr = &sa6->sin6_addr; port = ntohs(sa6->sin6_port);
//         }

//         if (addr) {
//             char tmp[INET6_ADDRSTRLEN];

//             if (inet_ntop(ss.ss_family, addr, tmp, sizeof(tmp)) != NULL) {
//                 strncpy(ipbuf, tmp, ipbuflen); ipbuf[ipbuflen-1] = 0;
//             } else { 
//                 ipbuf[0] = 0; 
//             }
//         }
//         if (out_port) *out_port = port;
//     }
//     return cfd;
// }

// int tcp_connect(const char* host, uint16_t port, int timeout_ms){
//     char service[16];
//     snprintf(service, sizeof(service), "%u", (unsigned)port);

//     struct addrinfo hints; memset(&hints, 0, sizeof(hints));
//     hints.ai_family   = AF_UNSPEC;
//     hints.ai_socktype = SOCK_STREAM;

//     struct addrinfo* res = NULL;
//     if (getaddrinfo(host, service, &hints, &res) != 0) {
//         set_last_err_from_errno(); return -1;
//     }

//     int fd = -1;

//     for (struct addrinfo* ai = res; ai; ai = ai->ai_next) {
//         int s = (int)socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
//         if (s < 0){ 
//             set_last_err_from_errno(); continue; 
//         }

//         if (timeout_ms > 0) {
//             if (ds_set_nonblocking(s, 1) != 0){ 
//                 close(s); s = -1; continue; 
//             }
//         }

//         int rc = connect(s, ai->ai_addr, (int)ai->ai_addrlen);
// #if defined(_WIN32)
//         bool in_progress = (rc != 0 && WSAGetLastError() == WSAEWOULDBLOCK);
// #else
//         bool in_progress = (rc != 0 && errno == EINPROGRESS);
// #endif

//         if (rc == 0) { fd = s; break; }
//         if (timeout_ms > 0 && in_progress) {
// #if defined(_WIN32)
//             WSAPOLLFD p = { 
//                 .fd = s, .events = POLLOUT, .revents = 0 
//             };

//             int n = WSAPoll(&p, 1, timeout_ms);

//             if (n == 1 && (p.revents & POLLOUT)) { 
//                 fd = s; break; 
//             }
// #else
//             struct pollfd p = { 
//                 .fd = s, .events = POLLOUT, .revents = 0 
//             };

//             int n = poll(&p, 1, timeout_ms);

//             if (n == 1 && (p.revents & POLLOUT)) { 
//                 fd = s; break; 
//             }
// #endif
//         }
//         close(s);
//     } 

//     freeaddrinfo(res);
//     if (fd >= 0 && timeout_ms > 0) ds_set_nonblocking(fd, 0);
//     if (fd < 0) set_last_err_from_errno();
//     return fd;
// }

// int send(int fd, const void* data, int len){
//     if (len <= 0) return 0;
// #if defined(_WIN32)
//     int n = send(fd, (const char*)data, len, 0);
// #else
//     int n = (int)send(fd, data, (size_t)len, 0);
// #endif
//     if (n < 0) set_last_err_from_errno();
//     return n;
// }

// int recv(int fd, void* data, int len){
//     if (len <= 0) return 0;
// #if defined(_WIN32)
//     int n = recv(fd, (char*)data, len, 0);
// #else
//     int n = (int)recv(fd, data, (size_t)len, 0);
// #endif
//     if (n < 0) set_last_err_from_errno();
//     return n;
// }

// int close(int fd){
//     if (close(fd) != 0){ 
//         set_last_err_from_errno(); return -1; 
//     }

//     return 0;
// }

// int poll(pollfd* fds, int nfds, int timeout_ms){
//     if (nfds <= 0) return 0;
// #if defined(_WIN32)
//     WSAPOLLFD stackfds[64];
//     WSAPOLLFD* pf = (nfds <= 64) ? stackfds : (WSAPOLLFD*)malloc(sizeof(WSAPOLLFD)*(size_t)nfds);

//     if (!pf){ 
//         set_last_err_from_errno(); return -1; 
//     }

//     for (int i=0;i<nfds;i++){ 
//         pf[i].fd = fds[i].fd; pf[i].events = 0; pf[i].revents = 0;
//         if (fds[i].events & 1) pf[i].events |= POLLIN;
//         if (fds[i].events & 2) pf[i].events |= POLLOUT;
//     }

//     int r = WSAPoll(pf, (ULONG)nfds, timeout_ms);

//     if (r >= 0){
//         for (int i=0;i<nfds;i++){
//             fds[i].revents = 0;
//             if (pf[i].revents & POLLIN)  fds[i].revents |= 1;
//             if (pf[i].revents & POLLOUT) fds[i].revents |= 2;
//         }
//     } else {
//         set_last_err_from_errno();
//     }
//     if (pf != stackfds) free(pf);
//     return r;
// #else
//     struct pollfd stackfds[64];
//     struct pollfd* pf = (nfds <= 64) ? stackfds : (struct pollfd*)malloc(sizeof(struct pollfd)*(size_t)nfds);

//     if (!pf){ 
//         set_last_err_from_errno(); return -1; 
//     }

//     for (int i=0;i<nfds;i++){ 
//         pf[i].fd = fds[i].fd; pf[i].events = 0; pf[i].revents = 0;
//         if (fds[i].events & 1) pf[i].events |= POLLIN;
//         if (fds[i].events & 2) pf[i].events |= POLLOUT;
//     }

//     int r = poll(pf, (nfds_t)nfds, timeout_ms);

//     if (r >= 0){
//         for (int i=0;i<nfds;i++){
//             fds[i].revents = 0;
//             if (pf[i].revents & POLLIN)  fds[i].revents |= 1;
//             if (pf[i].revents & POLLOUT) fds[i].revents |= 2;
//         }
//     } else {
//         set_last_err_from_errno();
//     }
//     if (pf != stackfds) free(pf);
//     return r;
// #endif
// }
