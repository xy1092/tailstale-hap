// Native 函数桥接层 - 调用 Rust C-ABI 函数

// 实际导入路径需要在 oh-package.json5 中配置
// import nativeModule from 'libhm_tailscale_native.so';

// NAPI 函数签名声明
declare interface NativeModule {
  wg_generate_keypair(): string
  wg_init_tunnel(configJson: string): string
  wg_create_socket(endpoint: string): number
  wg_start_loop(tunFd: number, sockFd: number): string
  wg_stop_loop(): string
  wg_get_stats(): string
  wg_close_tunnel(): string
  wg_free_string(ptr: number): void
  wg_free_buffer(ptr: number, len: number): void
  wg_process_tun_packet(data: ArrayBuffer, len: number): ArrayBuffer | null
  wg_process_network_packet(data: ArrayBuffer, len: number): ArrayBuffer | null
}

// 开发阶段用模拟实现，真机部署时替换为实际 .so 导入
let native: NativeModule;

try {
  // HarmonyOS 真机/模拟器上通过 NAPI 导入
  native = requireNative('hm_tailscale_native') as NativeModule;
} catch (_) {
  // 开发模拟
  console.warn('[NativeBridge] NAPI module not loaded, using stub');
  native = createStubNative();
}

function createStubNative(): NativeModule {
  // Generate inline stub keypair
  const stubPriv = 'aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890abcdefghijklmnop==';
  const stubPub = 'WIREGUARD_PUBLIC_KEY_STUB_32BYTES_B64_ENC==';
  let active = false;

  return {
    wg_generate_keypair(): string {
      return JSON.stringify({
        private_key: stubPriv,
        public_key: stubPub,
      });
    },
    wg_init_tunnel(_cfg: string): string {
      active = true;
      return '{"ok":true}';
    },
    wg_create_socket(_endpoint: string): number {
      return 42; // stub fd
    },
    wg_start_loop(_tunFd: number, _sockFd: number): string {
      return '{"ok":true}';
    },
    wg_stop_loop(): string {
      return '{"ok":true}';
    },
    wg_get_stats(): string {
      return JSON.stringify({
        handshake_completed: active,
        tx_bytes: 0,
        rx_bytes: 0,
        last_handshake_secs_ago: null,
        peer_endpoint: '',
      });
    },
    wg_close_tunnel(): string {
      active = false;
      return '{"ok":true}';
    },
    wg_free_string(_: number): void {},
    wg_free_buffer(_: number, _len: number): void {},
    wg_process_tun_packet(_: ArrayBuffer, _len: number): ArrayBuffer | null {
      return null;
    },
    wg_process_network_packet(_: ArrayBuffer, _len: number): ArrayBuffer | null {
      return null;
    },
  };
}

function parseNativeJson(raw: string): Record<string, Object> {
  try {
    return JSON.parse(raw) as Record<string, Object>;
  } catch {
    return { ok: false, error: 'parse error' };
  }
}

// ── 导出类型化的桥接方法 ──────────────────────────

export interface KeyPair {
  privateKey: string
  publicKey: string
}

export interface TunnelStats {
  handshake_completed: boolean
  tx_bytes: number
  rx_bytes: number
  last_handshake_secs_ago: number | null
  peer_endpoint: string
}

export class NativeBridge {
  static generateKeypair(): KeyPair {
    const raw = native.wg_generate_keypair();
    const parsed = parseNativeJson(raw);
    return {
      privateKey: parsed['private_key'] as string,
      publicKey: parsed['public_key'] as string,
    };
  }

  static initTunnel(configJson: string): boolean {
    const raw = native.wg_init_tunnel(configJson);
    const parsed = parseNativeJson(raw);
    return parsed['ok'] === true;
  }

  static createSocket(endpoint: string): number {
    return native.wg_create_socket(endpoint);
  }

  static startLoop(tunFd: number, sockFd: number): boolean {
    const raw = native.wg_start_loop(tunFd, sockFd);
    const parsed = parseNativeJson(raw);
    return parsed['ok'] === true;
  }

  static stopLoop(): void {
    native.wg_stop_loop();
  }

  static getStats(): TunnelStats {
    const raw = native.wg_get_stats();
    const parsed = parseNativeJson(raw);
    return {
      handshake_completed: (parsed['handshake_completed'] as boolean) ?? false,
      tx_bytes: (parsed['tx_bytes'] as number) ?? 0,
      rx_bytes: (parsed['rx_bytes'] as number) ?? 0,
      last_handshake_secs_ago: (parsed['last_handshake_secs_ago'] as number) ?? null,
      peer_endpoint: (parsed['peer_endpoint'] as string) ?? '',
    };
  }

  static closeTunnel(): boolean {
    const raw = native.wg_close_tunnel();
    const parsed = parseNativeJson(raw);
    return parsed['ok'] === true;
  }
}
