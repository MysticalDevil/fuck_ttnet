import type { DiagnosticsData } from "./types";

/**
 * Keys whose values carry account, device or session identity.
 *
 * Keep in sync with `redaction_keys` in scripts/status.sh. The backend already
 * redacts the log excerpts it emits, but that is a single point of failure and
 * the copied payload is built from whatever the backend printed. Anything this
 * list misses must still not leak, which is why the copy path also runs
 * `redactDiagnostics` as a second pass.
 */
export const REDACTION_KEYS = [
  "device_id",
  "iid",
  "install_id",
  "openudid",
  "cdid",
  "sessionid",
  "sid_tt",
  "sec_user_id",
  "sec_uid",
  "token",
  "msToken",
  "ms_token",
  "odin_tt",
  "passport_csrf_token",
  "passport_csrf_token_default",
  "x-tt-token",
  "x-gorgon",
  "tt-token",
] as const;

export const REDACTED_VALUE = "[REDACTED]";

/**
 * Fields allowed into a copied diagnostics report. Everything else the backend
 * prints is dropped rather than copied, so a future backend field cannot leak
 * an identity value just because nobody updated the key list above.
 */
export const COPYABLE_FIELDS = [
  "status",
  "summary",
  "diagnosis_id",
  "diagnosis_title",
  "transport_stage",
  "repair_action",
  "repairability",
  "recommended_action",
  "package",
  "module_version",
  "tiktok_pid",
  "network_validated",
  "server_json",
  "tt_net_config",
  "server_global_drop_hits",
  "server_literal_hits",
  "tt_net_config_hits",
  "keva_tnc_hits",
  "keva_multi_hits",
  "recent_ttnet_error_count",
  "recent_tls_error_count",
  "recent_ui_signal_count",
  "server_json_mtime",
  "server_json_size",
  "tt_net_config_mtime",
  "tt_net_config_size",
  "carrier_region",
  "carrier_region_v2",
  "mcc_mnc",
  "region",
  "current_region",
  "sys_region",
  "recent_errors",
  "recent_tls_errors",
  "recent_ui_signals",
  "latest_region_line",
  "module_log",
] as const;

const KEYS_ALTERNATION = REDACTION_KEYS.map((key) =>
  key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
)
  .sort((a, b) => b.length - a.length)
  .join("|");

// Applied in order. Each mirrors a shape the backend emits or a logcat emitters
// uses. The trailing group keeps the original separator so the report stays
// readable.
const REDACTION_RULES: Array<[RegExp, string]> = [
  // {"sec_uid":"..."}
  [
    new RegExp(`("(?:${KEYS_ALTERNATION})"\\s*:\\s*")[^"]*`, "gi"),
    `$1${REDACTED_VALUE}`,
  ],
  // x-tt-token: abc  /  sessionid: abc
  [
    new RegExp(`((?:${KEYS_ALTERNATION})\\s*:\\s*)[^\\s]+`, "gi"),
    `$1${REDACTED_VALUE}`,
  ],
  // device_id=abc  /  device_id = abc
  [
    new RegExp(`((?:${KEYS_ALTERNATION})\\s*=\\s*)[^&"\\s@$]*`, "gi"),
    `$1${REDACTED_VALUE}`,
  ],
  // device_id&#*abc@$*   (TTNet TNC separator)
  [
    new RegExp(`((?:${KEYS_ALTERNATION})&#\\*)[^@]*`, "gi"),
    `$1${REDACTED_VALUE}`,
  ],
  // Whole-line credential headers.
  [/(authorization\s*:\s*).*/gi, `$1${REDACTED_VALUE}`],
  [/(cookie\s*:\s*).*/gi, `$1${REDACTED_VALUE}`],
];

/** Redact every known identity shape in a free-form string. */
export function redactText(value: string): string {
  let result = value;
  for (const [pattern, replacement] of REDACTION_RULES) {
    result = result.replace(pattern, replacement);
  }
  return result;
}

/**
 * Second-pass redaction over a parsed diagnostics payload. Unknown fields are
 * dropped, and every retained value is run through `redactText`.
 */
export function redactDiagnostics(
  data: DiagnosticsData,
): Record<string, string> {
  const output: Record<string, string> = {};

  for (const field of COPYABLE_FIELDS) {
    const value = data[field];
    if (typeof value === "string" && value.length > 0) {
      output[field] = redactText(value);
    }
  }

  return output;
}
