// Headscale REST API 客户端 (带重试和错误处理)

import http from '@ohos.net.http';
import type {
  HeadscaleConfig, NodeInfo, RegisterRequest, RegisterResponse, PeerConfig
} from './types';

const MAX_RETRIES = 3;
const RETRY_DELAY_MS = 1000;

export class NetworkError extends Error {
  constructor(message: string, public code?: number) {
    super(message);
    this.name = 'NetworkError';
  }
}

export class HeadscaleClient {
  private config: HeadscaleConfig;

  constructor(config: HeadscaleConfig) {
    this.config = config;
  }

  private async retryDelay(attempt: number): Promise<void> {
    return new Promise<void>(resolve => {
      setTimeout(() => resolve(), RETRY_DELAY_MS * Math.pow(2, attempt));
    });
  }

  private async request<T>(method: http.RequestMethod,
                           path: string,
                           body?: object): Promise<T> {
    let lastError: Error | null = null;

    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
      const req = http.createHttp();
      try {
        const url = `${this.config.serverUrl}${path}`;
        const opts: http.HttpRequestOptions = {
          method: method,
          header: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${this.config.apiKey}`,
          },
          connectTimeout: 10000,
          readTimeout: 15000,
        };

        if (body) {
          opts.extraData = JSON.stringify(body);
        }

        const resp = await req.request(url, opts);

        if (resp.responseCode === 200 || resp.responseCode === 201) {
          const text = typeof resp.result === 'string'
            ? resp.result
            : JSON.stringify(resp.result);
          return JSON.parse(text) as T;
        }

        if (resp.responseCode >= 500) {
          throw new NetworkError(
            `Server error ${resp.responseCode}: ${resp.result}`,
            resp.responseCode
          );
        }

        throw new NetworkError(
          `API error ${resp.responseCode}: ${resp.result}`,
          resp.responseCode
        );
      } catch (e) {
        lastError = e instanceof Error ? e : new Error(String(e));

        // 不重试客户端错误 (4xx)
        if (e instanceof NetworkError && e.code && e.code < 500) {
          throw e;
        }

        // 最后一次尝试，直接抛出
        if (attempt < MAX_RETRIES - 1) {
          console.warn(`[HeadscaleClient] request failed, retry ${attempt + 1}/${MAX_RETRIES}: ${lastError.message}`);
          await this.retryDelay(attempt);
        }
      } finally {
        req.destroy();
      }
    }

    throw new NetworkError(
      `Request failed after ${MAX_RETRIES} retries: ${lastError?.message}`
    );
  }

  async registerNode(req: RegisterRequest): Promise<RegisterResponse> {
    return this.request<RegisterResponse>(
      http.RequestMethod.POST,
      '/api/v1/node/register',
      { node_key: req.nodeKey, name: req.name, user: req.user }
    );
  }

  async listNodes(): Promise<NodeInfo[]> {
    const result = await this.request<{ nodes: NodeInfo[] }>(
      http.RequestMethod.GET,
      '/api/v1/node'
    );
    return result.nodes ?? [];
  }

  async getNode(nodeId: string): Promise<NodeInfo> {
    const result = await this.request<{ node: NodeInfo }>(
      http.RequestMethod.GET,
      `/api/v1/node/${nodeId}`
    );
    return result.node;
  }

  async expireNode(nodeId: string): Promise<void> {
    await this.request<unknown>(
      http.RequestMethod.DELETE,
      `/api/v1/node/${nodeId}`
    );
  }

  async buildPeerConfig(myKey: string): Promise<PeerConfig[]> {
    const nodes = await this.listNodes();
    return nodes
      .filter(n => n.publicKey !== myKey && n.online)
      .map(n => ({
        publicKey: n.publicKey,
        endpoint: n.endpoints[0] ?? '',
        allowedIps: n.ipAddresses,
      }));
  }

  async healthCheck(): Promise<boolean> {
    try {
      await this.request<unknown>(http.RequestMethod.GET, '/api/v1/node');
      return true;
    } catch {
      return false;
    }
  }
}
