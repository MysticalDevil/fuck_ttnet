export interface ExecResult {
  errno: number;
  stdout: string;
  stderr: string;
}

export interface KernelSUApi {
  exec(command: string, optionsJson: string, callbackName: string): void;
  toast?(message: string): void;
}

declare global {
  interface Window {
    ksu?: KernelSUApi;
    [key: string]: unknown;
  }
}

export interface DiagnosticsData {
  [key: string]: string | undefined;
  status?: string;
  summary?: string;
  diagnosis_id?: string;
  diagnosis_title?: string;
  transport_stage?: string;
  repair_action?: string;
  repairability?: string;
  recommended_action?: string;
  package?: string;
  module_version?: string;
  tiktok_pid?: string;
  network_validated?: string;
  server_json?: string;
  tt_net_config?: string;
  server_global_drop_hits?: string;
  server_literal_hits?: string;
  tt_net_config_hits?: string;
  keva_tnc_hits?: string;
  keva_multi_hits?: string;
  recent_ttnet_error_count?: string;
  recent_tls_error_count?: string;
  recent_ui_signal_count?: string;
  server_json_mtime?: string;
  server_json_size?: string;
  tt_net_config_mtime?: string;
  tt_net_config_size?: string;
  carrier_region?: string;
  carrier_region_v2?: string;
  mcc_mnc?: string;
  region?: string;
  current_region?: string;
  sys_region?: string;
  recent_errors?: string;
  recent_tls_errors?: string;
  recent_ui_signals?: string;
  latest_region_line?: string;
  module_log?: string;
}

export interface RepairMeta {
  label: string;
  repairable: boolean;
}

export type RefreshState = "idle" | "loading" | "success" | "error";
export type LogTabName = "ttnet" | "tls" | "ui" | "module" | "command";
export type Tone = "neutral" | "ok" | "warn" | "danger" | "accent" | "clean" | "blocked" | "dirty" | "warning";

export interface LogTabDetails {
  title: string;
  meta: string;
  text: string;
}
