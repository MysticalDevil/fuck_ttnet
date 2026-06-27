import { getById, queryRequired } from "./dom";
import {
  buildLogTabMap,
  chooseDefaultLogTab,
  formatBool,
  formatPathWithMeta,
  repairMeta,
  statusSubtitle,
  statusTitle,
} from "./diagnostics";
import type {
  DiagnosticsData,
  LogTabName,
  RefreshState,
  Tone,
} from "./types";

export class DiagnosticsRenderer {
  private lastDiagnostics: DiagnosticsData | null = null;
  private activeLogTab: LogTabName = "ttnet";
  private lastClientRefreshAt: Date | null = null;
  private lastCommandOutput = "No command output yet.";
  private refreshStateTimer: number | null = null;

  setBusy(isBusy: boolean): void {
    (["refresh", "force-stop", "copy-diagnostics", "auto-refresh"] as const).forEach((id) => {
      getById<HTMLInputElement | HTMLButtonElement>(id).disabled = isBusy;
    });

    const runFix = getById<HTMLButtonElement>("run-fix");
    const hasRepair = runFix.dataset.repairable === "yes";
    runFix.disabled = isBusy || !hasRepair;
  }

  setRefreshState(state: RefreshState, detail?: string): void {
    this.clearRefreshStateTimer();

    const refreshButton = getById<HTMLButtonElement>("refresh");
    const refreshState = getById<HTMLElement>("refresh-state");
    const refreshLabel = getById<HTMLElement>("refresh-label");
    const refreshSubtext = getById<HTMLElement>("refresh-subtext");
    const refreshDetail = getById<HTMLElement>("refresh-detail");

    refreshButton.dataset.state = state;

    if (state === "loading") {
      refreshState.textContent = "Live check running";
      refreshState.dataset.tone = "accent";
      refreshLabel.textContent = "Refreshing";
      refreshSubtext.textContent = "Running status.sh on device";
      refreshDetail.textContent =
        detail || "KernelSU is executing status.sh on the device.";
      return;
    }

    if (state === "success") {
      refreshState.textContent = "Device state updated";
      refreshState.dataset.tone = "ok";
      refreshLabel.textContent = "Refresh complete";
      refreshSubtext.textContent = this.lastRefreshLabel();
      refreshDetail.textContent =
        detail || "Live TTNet diagnostics were pulled successfully.";
      this.refreshStateTimer = window.setTimeout(() => {
        this.setRefreshState("idle");
      }, 4800);
      return;
    }

    if (state === "error") {
      refreshState.textContent = "Refresh failed";
      refreshState.dataset.tone = "danger";
      refreshLabel.textContent = "Retry refresh";
      refreshSubtext.textContent = detail || "Status check failed";
      refreshDetail.textContent =
        detail || "KernelSU WebUI could not complete the status check.";
      this.refreshStateTimer = window.setTimeout(() => {
        this.setRefreshState("idle");
      }, 5200);
      return;
    }

    refreshState.textContent = "Idle";
    refreshState.dataset.tone = "neutral";
    refreshLabel.textContent = "Refresh now";
    refreshSubtext.textContent = this.lastRefreshLabel();
    refreshDetail.textContent =
      "Pull live TTNet status, file evidence, and recent runtime signals.";
  }

  render(data: DiagnosticsData): void {
    this.lastDiagnostics = data;
    this.lastClientRefreshAt = new Date();

    const status = data.status || "unknown";
    const statusLabel = statusTitle(status);
    const card = getById<HTMLElement>("status-card");
    card.className = `status-hero is-${status}`;

    this.setText("status-title", data.diagnosis_title || statusLabel);
    this.setText("status-pill", statusLabel);
    this.setText("status-summary", data.summary);
    this.setText("recommended-action", data.recommended_action);
    this.setText("repairability", data.repairability);
    this.setText("subtitle", statusSubtitle(status));

    this.setText("diagnosis-id", data.diagnosis_id);
    this.setText("transport-stage", data.transport_stage);
    this.setText("recent-ui-count", data.recent_ui_signal_count || 0);
    this.setText(
      "latest-region-line",
      data.latest_region_line || "No recent TikTok region trace.",
    );

    this.setText("tiktok-pid", data.tiktok_pid || "not running");
    this.setText(
      "network-validated",
      formatBool(data.network_validated, "Validated", "Not validated"),
    );
    this.setText("module-version", data.module_version);
    this.setText("package-name", data.package);

    this.setText("carrier-region", data.carrier_region || "Unavailable");
    this.setText("carrier-region-v2", data.carrier_region_v2 || "Unavailable");
    this.setText("mcc-mnc", data.mcc_mnc || "Unavailable");
    this.setText(
      "regions",
      [data.region, data.current_region, data.sys_region].filter(Boolean).join(" / ") ||
        "No region trace captured",
    );

    this.setText("server-json-path", data.server_json);
    this.setText(
      "server-mtime",
      formatPathWithMeta(data.server_json_mtime, data.server_json_size),
    );
    this.setText("tt-net-config-path", data.tt_net_config);
    this.setText(
      "config-mtime",
      formatPathWithMeta(data.tt_net_config_mtime, data.tt_net_config_size),
    );
    this.setText("server-rule", data.server_global_drop_hits);
    this.setText("server-literal", data.server_literal_hits);
    this.setText("config-hits", data.tt_net_config_hits);
    this.setText(
      "keva-hits",
      `${data.keva_tnc_hits || 0} / ${data.keva_multi_hits || 0}`,
    );

    this.setMetric(
      "recent-ttnet-count",
      String(data.recent_ttnet_error_count || 0),
      Number(data.recent_ttnet_error_count || 0) > 0 ? "danger" : "ok",
    );
    this.setMetric(
      "recent-tls-count",
      String(data.recent_tls_error_count || 0),
      Number(data.recent_tls_error_count || 0) > 0 ? "warn" : "ok",
    );

    this.setMetaPill(
      "meta-updated",
      `Updated ${this.lastClientRefreshAt.toLocaleTimeString([], {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      })}`,
      "neutral",
    );
    this.setMetaPill(
      "meta-network",
      formatBool(
        data.network_validated,
        "Android network validated",
        "Android network not validated",
      ),
      data.network_validated === "yes" ? "ok" : "warn",
    );
    this.setMetaPill(
      "meta-package",
      data.package || "TikTok package unknown",
      "neutral",
    );

    this.setInlineBadge("diagnosis-id-badge", data.diagnosis_id || "-", status as Tone);
    this.setInlineBadge(
      "runtime-badge",
      data.tiktok_pid && data.tiktok_pid !== "not running"
        ? "TikTok running"
        : "TikTok stopped",
      data.tiktok_pid && data.tiktok_pid !== "not running" ? "ok" : "neutral",
    );
    this.setInlineBadge(
      "region-badge",
      data.latest_region_line ? "Trace captured" : "No trace",
      data.latest_region_line ? "ok" : "neutral",
    );
    this.setInlineBadge(
      "file-badge",
      `${data.server_json_size || 0} / ${data.tt_net_config_size || 0} bytes`,
      "neutral",
    );
    this.setInlineBadge(
      "evidence-badge",
      `${data.recent_ttnet_error_count || 0}/${data.recent_tls_error_count || 0}/${data.recent_ui_signal_count || 0}`,
      status as Tone,
    );

    const repair = repairMeta(data.repair_action);
    const runFix = getById<HTMLButtonElement>("run-fix");
    const primaryActions = queryRequired<HTMLDivElement>(".primary-actions");
    runFix.textContent = repair.label;
    runFix.dataset.repairable = repair.repairable ? "yes" : "no";
    runFix.classList.toggle("is-hidden", !repair.repairable);
    primaryActions.classList.toggle("is-repairless", !repair.repairable);
    runFix.disabled = !repair.repairable;

    this.activeLogTab = chooseDefaultLogTab(data, this.activeLogTab);
    this.renderEvidence(data);
  }

  updateCommandOutput(value: string): void {
    this.lastCommandOutput = value && value.trim() ? value : "No command output yet.";
    if (this.lastDiagnostics) {
      this.renderEvidence(this.lastDiagnostics);
    }
  }

  setActiveLogTab(nextTab: LogTabName): void {
    this.activeLogTab = nextTab;
    if (this.lastDiagnostics) {
      this.renderEvidence(this.lastDiagnostics);
    }
  }

  hasDiagnostics(): boolean {
    return this.lastDiagnostics != null;
  }

  getCopyPayload(): string {
    if (!this.lastDiagnostics) {
      throw new Error("No diagnostics yet");
    }

    return JSON.stringify(
      {
        refreshed_at: this.lastClientRefreshAt
          ? this.lastClientRefreshAt.toISOString()
          : null,
        diagnostics: this.lastDiagnostics,
      },
      null,
      2,
    );
  }

  showError(message: string): void {
    this.setText("status-title", "Error");
    this.setText("status-summary", message);
  }

  private renderEvidence(data: DiagnosticsData): void {
    const tabs = buildLogTabMap(data, this.lastCommandOutput);
    if (!tabs[this.activeLogTab]) {
      this.activeLogTab = "ttnet";
    }

    document.querySelectorAll<HTMLButtonElement>(".log-tab").forEach((button) => {
      button.classList.toggle("is-active", button.dataset.logTab === this.activeLogTab);
    });

    const active = tabs[this.activeLogTab];
    this.setText("evidence-title", active.title);
    this.setText("evidence-meta", active.meta);
    this.setLogText("evidence-log", active.text, "No evidence available.");
  }

  private clearRefreshStateTimer(): void {
    if (this.refreshStateTimer != null) {
      window.clearTimeout(this.refreshStateTimer);
      this.refreshStateTimer = null;
    }
  }

  private lastRefreshLabel(): string {
    if (!this.lastClientRefreshAt) {
      return "Waiting for first refresh";
    }
    return `Last sync ${this.lastClientRefreshAt.toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    })}`;
  }

  private setText(id: string, value: string | number | null | undefined): void {
    getById<HTMLElement>(id).textContent =
      value === "" || value == null ? "-" : String(value);
  }

  private setLogText(id: string, value: string | undefined, fallback: string): void {
    getById<HTMLElement>(id).textContent = value && value.trim() ? value : fallback;
  }

  private setMetaPill(id: string, label: string, tone: Tone): void {
    const target = getById<HTMLElement>(id);
    target.textContent = label;
    target.dataset.tone = tone;
  }

  private setInlineBadge(id: string, label: string, tone: Tone): void {
    const target = getById<HTMLElement>(id);
    target.textContent = label;
    target.dataset.tone = tone;
  }

  private setMetric(id: string, value: string, tone: Tone): void {
    const target = getById<HTMLElement>(id);
    target.textContent = value;
    target.dataset.tone = tone;
  }
}
