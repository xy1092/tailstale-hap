// NAPI Bridge - 将 Rust C-ABI 函数注册到 HarmonyOS NAPI 运行时
//
// 使用标准 Node-API 头文件 (与 HarmonyOS NAPI 兼容)
// 交叉编译:
//   aarch64-linux-gnu-gcc -shared -fPIC -I/usr/include/node \
//     napi_bridge.c -Ltarget/aarch64-unknown-linux-gnu/release \
//     -lhm_tailscale_native -lpthread -lm -o libhm_tailscale_native.so

#include <node_api.h>
#include <string.h>
#include <stdlib.h>

// Rust extern declarations
extern char* wg_generate_keypair(void);
extern char* wg_init_tunnel(const char* config_json);
extern int   wg_create_socket(const char* endpoint);
extern char* wg_start_loop(int tun_fd, int sock_fd);
extern char* wg_stop_loop(void);
extern char* wg_get_stats(void);
extern char* wg_close_tunnel(void);
extern void  wg_free_string(char* ptr);

// ── NAPI Wrappers ──────────────────────────────────────────

static napi_value Napi_GenerateKeypair(napi_env env, napi_callback_info info) {
    char* result = wg_generate_keypair();
    napi_value js_result;
    napi_create_string_utf8(env, result, NAPI_AUTO_LENGTH, &js_result);
    wg_free_string(result);
    return js_result;
}

static napi_value Napi_InitTunnel(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);

    size_t len;
    napi_get_value_string_utf8(env, args[0], NULL, 0, &len);
    char* config = (char*)malloc(len + 1);
    napi_get_value_string_utf8(env, args[0], config, len + 1, &len);

    char* result = wg_init_tunnel(config);
    free(config);

    napi_value js_result;
    napi_create_string_utf8(env, result, NAPI_AUTO_LENGTH, &js_result);
    wg_free_string(result);
    return js_result;
}

static napi_value Napi_CreateSocket(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);

    size_t len;
    napi_get_value_string_utf8(env, args[0], NULL, 0, &len);
    char* endpoint = (char*)malloc(len + 1);
    napi_get_value_string_utf8(env, args[0], endpoint, len + 1, &len);

    int fd = wg_create_socket(endpoint);
    free(endpoint);

    napi_value js_result;
    napi_create_int32(env, fd, &js_result);
    return js_result;
}

static napi_value Napi_StartLoop(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, NULL, NULL);

    int32_t tun_fd, sock_fd;
    napi_get_value_int32(env, args[0], &tun_fd);
    napi_get_value_int32(env, args[1], &sock_fd);

    char* result = wg_start_loop(tun_fd, sock_fd);
    napi_value js_result;
    napi_create_string_utf8(env, result, NAPI_AUTO_LENGTH, &js_result);
    wg_free_string(result);
    return js_result;
}

static napi_value Napi_StopLoop(napi_env env, napi_callback_info info) {
    char* result = wg_stop_loop();
    napi_value js_result;
    napi_create_string_utf8(env, result, NAPI_AUTO_LENGTH, &js_result);
    wg_free_string(result);
    return js_result;
}

static napi_value Napi_GetStats(napi_env env, napi_callback_info info) {
    char* result = wg_get_stats();
    napi_value js_result;
    napi_create_string_utf8(env, result, NAPI_AUTO_LENGTH, &js_result);
    wg_free_string(result);
    return js_result;
}

static napi_value Napi_CloseTunnel(napi_env env, napi_callback_info info) {
    char* result = wg_close_tunnel();
    napi_value js_result;
    napi_create_string_utf8(env, result, NAPI_AUTO_LENGTH, &js_result);
    wg_free_string(result);
    return js_result;
}

// ── Module Registration ────────────────────────────────────

static napi_value InitModule(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"wg_generate_keypair", NULL, Napi_GenerateKeypair,
         NULL, NULL, NULL, napi_default, NULL},
        {"wg_init_tunnel",      NULL, Napi_InitTunnel,
         NULL, NULL, NULL, napi_default, NULL},
        {"wg_create_socket",    NULL, Napi_CreateSocket,
         NULL, NULL, NULL, napi_default, NULL},
        {"wg_start_loop",       NULL, Napi_StartLoop,
         NULL, NULL, NULL, napi_default, NULL},
        {"wg_stop_loop",        NULL, Napi_StopLoop,
         NULL, NULL, NULL, napi_default, NULL},
        {"wg_get_stats",        NULL, Napi_GetStats,
         NULL, NULL, NULL, napi_default, NULL},
        {"wg_close_tunnel",     NULL, Napi_CloseTunnel,
         NULL, NULL, NULL, napi_default, NULL},
    };

    napi_define_properties(
        env, exports,
        sizeof(desc) / sizeof(desc[0]),
        desc
    );

    return exports;
}

NAPI_MODULE(hm_tailscale_native, InitModule)
