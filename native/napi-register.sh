# NAPI 模块注册桥接文件
# 当使用 DevEco Studio + HarmonyOS NDK 编译时，此文件用于生成 NAPI 绑定

# 生成 TypeScript 类型声明
generate_ts() {
  cat <<'EOF' > ../entry/src/main/ets/vpn/NapiModule.d.ts
declare module 'libhm_tailscale_native.so' {
  export function wg_generate_keypair(): string;
  export function wg_init_tunnel(configJson: string): string;
  export function wg_create_socket(endpoint: string): number;
  export function wg_start_loop(tunFd: number, sockFd: number): string;
  export function wg_stop_loop(): string;
  export function wg_get_stats(): string;
  export function wg_close_tunnel(): string;
  export function wg_free_string(ptr: number): void;
  export function wg_free_buffer(ptr: number, len: number): void;
}

declare function requireNative(moduleName: string): any;
EOF
  echo "Generated TypeScript declarations"
}

case "$1" in
  gen-ts) generate_ts ;;
  *) echo "Usage: $0 gen-ts" ;;
esac
