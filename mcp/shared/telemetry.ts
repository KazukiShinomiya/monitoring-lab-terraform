/**
 * 共通計装ヘルパー（4 MCP サーバーで再利用）
 *
 * 役割: ツール呼び出しの回数・レイテンシ・成否を計測し、OTLP/gRPC で
 *       otel-collector へ push する。短命プロセスのため、終了時の flush が
 *       唯一の確実な送出経路（research.md D4）。
 *
 * 設計上の確定事項（specs/016 analyze 反映）:
 *  - `service` / `tool` / `status` は Resource 任せにせず、データポイント属性として
 *    明示付与する（exporter の Resource ラベル化で `service_name` に化ける罠を回避 / I1）。
 *  - Histogram のバケット境界は MeterProvider の View で登録する（A1）。
 *  - temporality は cumulative（Prometheus カウンタ互換）。
 */
import { metrics, type Counter, type Histogram, type Attributes } from '@opentelemetry/api';
import {
  MeterProvider,
  PeriodicExportingMetricReader,
  InstrumentType,
  AggregationType,
  AggregationTemporality,
} from '@opentelemetry/sdk-metrics';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-grpc';
import { resourceFromAttributes } from '@opentelemetry/resources';
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
} from '@opentelemetry/semantic-conventions';

const METRIC_INVOCATIONS = 'mcp_tool_invocations_total';
const METRIC_DURATION = 'mcp_tool_duration_seconds';

/** レイテンシ Histogram の明示バケット境界（秒）。data-model.md と一致させること。 */
const DURATION_BUCKETS_SECONDS = [
  0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30,
];

const DEFAULT_ENDPOINT = 'http://10.0.0.220:4317';

let provider: MeterProvider | undefined;
let invocationCounter: Counter | undefined;
let durationHistogram: Histogram | undefined;
let serviceLabel = 'unknown';
let disabled = false;
let initialized = false;
let shutdownDone = false;

/** `MCP_TELEMETRY_DISABLED=1` で計測を完全に無効化する（FR-012）。 */
function telemetryDisabledByEnv(): boolean {
  return process.env.MCP_TELEMETRY_DISABLED === '1';
}

/**
 * MeterProvider を初期化し OTLP exporter を接続する。
 * 冪等（2回目以降は no-op）。接続不能でも例外を投げない（起動を妨げない）。
 */
export function initTelemetry(serviceName: string): void {
  if (initialized) return; // 冪等
  initialized = true;

  if (telemetryDisabledByEnv()) {
    disabled = true;
    return;
  }

  serviceLabel = serviceName;

  try {
    const endpoint =
      process.env.OTEL_EXPORTER_OTLP_ENDPOINT ?? DEFAULT_ENDPOINT;

    const exporter = new OTLPMetricExporter({
      url: endpoint,
      // cumulative temporality を明示（Prometheus / VictoriaMetrics 互換）
      temporalityPreference: AggregationTemporality.CUMULATIVE,
    });

    const reader = new PeriodicExportingMetricReader({
      exporter,
      // 短命コンテナでは発火しないことが多い。確実な送出は shutdownTelemetry が担う。
      exportIntervalMillis: 30000,
    });

    provider = new MeterProvider({
      resource: resourceFromAttributes({
        [ATTR_SERVICE_NAME]: `mcp-${serviceName}`,
        [ATTR_SERVICE_VERSION]: process.env.npm_package_version ?? '0.0.0',
      }),
      readers: [reader],
      // A1: バケット境界は View で登録する（計装時ではなく初期化時）
      views: [
        {
          instrumentName: METRIC_DURATION,
          instrumentType: InstrumentType.HISTOGRAM,
          aggregation: {
            type: AggregationType.EXPLICIT_BUCKET_HISTOGRAM,
            options: {
              boundaries: DURATION_BUCKETS_SECONDS,
              recordMinMax: true,
            },
          },
        },
      ],
    });

    metrics.setGlobalMeterProvider(provider);
    const meter = provider.getMeter('mcp-telemetry');
    invocationCounter = meter.createCounter(METRIC_INVOCATIONS, {
      description: 'MCP ツール呼び出しの累積回数',
    });
    durationHistogram = meter.createHistogram(METRIC_DURATION, {
      description: 'MCP ツール実行時間',
      unit: 's',
    });
  } catch (err) {
    // best-effort: 計測の初期化失敗がサーバー起動を妨げてはならない（FR-007）
    process.stderr.write(`[telemetry] init failed: ${String(err)}\n`);
    provider = undefined;
    invocationCounter = undefined;
    durationHistogram = undefined;
  }
}

/**
 * ツールハンドラをラップして計測を付加する。
 * 戻り値・例外はそのまま透過する（FR-011）。計測自体の失敗は握りつぶす（FR-007）。
 */
export function instrumentTool<A extends unknown[], R>(
  toolName: string,
  handler: (...args: A) => R | Promise<R>,
): (...args: A) => Promise<R> {
  return async (...args: A): Promise<R> => {
    // 無効時・未初期化時は素通し（計測ゼロオーバーヘッド）
    if (disabled || !invocationCounter) {
      return await handler(...args);
    }
    const startNs = process.hrtime.bigint();
    try {
      const result = await handler(...args);
      record('success', toolName, startNs);
      return result;
    } catch (err) {
      record('error', toolName, startNs);
      throw err; // 例外は透過
    }
  };
}

function record(
  status: 'success' | 'error',
  tool: string,
  startNs: bigint,
): void {
  try {
    const seconds = Number(process.hrtime.bigint() - startNs) / 1e9;
    // I1: service / tool / status を明示データポイント属性として付与
    const attrs: Attributes = { service: serviceLabel, tool };
    invocationCounter?.add(1, { ...attrs, status });
    durationHistogram?.record(seconds, attrs);
  } catch {
    // best-effort: 計測がツール応答を阻害してはならない
  }
}

/**
 * 未送出メトリクスを flush し MeterProvider を shutdown する（FR-006）。
 * timeoutMs を超えたら諦めて resolve（収集先到達不能でもプロセス終了を阻害しない）。
 * 冪等。
 */
export async function shutdownTelemetry(timeoutMs = 2000): Promise<void> {
  if (disabled || shutdownDone || !provider) return;
  shutdownDone = true;
  const current = provider;
  await Promise.race([
    current.shutdown().catch(() => {
      /* best-effort */
    }),
    new Promise<void>((resolve) => {
      const t = setTimeout(resolve, timeoutMs);
      // タイマーがプロセス終了を引き止めないように
      if (typeof t.unref === 'function') t.unref();
    }),
  ]);
}

/** テスト用: 内部状態を初期化前に戻す（本番コードからは呼ばない）。 */
export function __resetForTest(): void {
  provider = undefined;
  invocationCounter = undefined;
  durationHistogram = undefined;
  serviceLabel = 'unknown';
  disabled = false;
  initialized = false;
  shutdownDone = false;
}
