import type {
  DiagnosticsData,
  LogTabDetails,
  LogTabName,
  RepairMeta,
} from "./types";

export function wait(ms: number): Promise<void> {
  return new Promise((resolve) => {
    window.setTimeout(resolve, ms);
  });
}

export function compactText(
  value: string | undefined,
  fallback = "No recent signal.",
): string {
  return value && value.trim() ? value : fallback;
}

export function statusTitle(status: string): string {
  if (status === "clean") return "Clean";
  if (status === "blocked") return "Blocked";
  if (status === "dirty") return "Needs Attention";
  if (status === "warning") return "External Issue";
  return "Unknown";
}

export function statusSubtitle(status: string): string {
  if (status === "clean") return "No active local TTNet block detected.";
  if (status === "blocked") return "Local TTNet policy is actively blocking requests.";
  if (status === "dirty") return "Cached metadata still needs cleanup.";
  if (status === "warning") return "Signals point to a transport or external policy issue.";
  return "Waiting for TikTok diagnostics.";
}

export function repairMeta(action: string | undefined): RepairMeta {
  if (action === "patch_local_ttnet") {
    return { label: "Repair Local TTNet", repairable: true };
  }
  if (action === "reset_runtime_cache") {
    return { label: "Reset Runtime Cache", repairable: true };
  }
  return { label: "No Local Repair", repairable: false };
}

export function formatBool(
  value: string | undefined,
  trueLabel: string,
  falseLabel: string,
): string {
  if (value === "yes") return trueLabel;
  if (value === "no") return falseLabel;
  return "Unknown";
}

export function formatPathWithMeta(
  mtime: string | undefined,
  size: string | undefined,
): string {
  const parts: string[] = [];
  if (mtime && mtime !== "-" && mtime !== "missing") {
    parts.push(mtime);
  } else if (mtime) {
    parts.push(mtime);
  }
  if (size && size !== "0") {
    parts.push(`${size} bytes`);
  } else if (size === "0") {
    parts.push("0 bytes");
  }
  return parts.length > 0 ? parts.join(" / ") : "Unavailable";
}

export function chooseDefaultLogTab(
  data: DiagnosticsData,
  activeLogTab: LogTabName,
): LogTabName {
  if (data.status === "blocked") return "ttnet";
  if (data.diagnosis_id === "tls_cert_authority_invalid") return "tls";
  if (data.diagnosis_id === "ui_only_generic_or_region_unavailable") return "ui";
  return activeLogTab;
}

export function buildLogTabMap(
  data: DiagnosticsData,
  lastCommandOutput: string,
): Record<LogTabName, LogTabDetails> {
  return {
    ttnet: {
      title: "Recent TTNet Drops",
      meta: `${data.recent_ttnet_error_count || 0} recent matches`,
      text: compactText(data.recent_errors, "No recent -555 TTNet drop."),
    },
    tls: {
      title: "Recent TLS Errors",
      meta: `${data.recent_tls_error_count || 0} recent matches`,
      text: compactText(data.recent_tls_errors, "No recent TLS trust failure."),
    },
    ui: {
      title: "Recent UI Signals",
      meta: `${data.recent_ui_signal_count || 0} recent matches`,
      text: compactText(
        data.recent_ui_signals,
        "No recent generic UI no-network signal.",
      ),
    },
    module: {
      title: "Module Log",
      meta: "Latest patch or passive-service messages",
      text: compactText(data.module_log, "No module log yet."),
    },
    command: {
      title: "Command Output",
      meta: "Most recent WebUI action output",
      text: lastCommandOutput,
    },
  };
}

export function parseStatusOutput(stdout: string): DiagnosticsData {
  const data: DiagnosticsData = {};
  const lines = stdout.split(/\r?\n/);

  for (let index = 0; index < lines.length; index += 1) {
    const heredoc = lines[index]?.match(/^([A-Za-z0-9_]+)<<EOF$/);
    if (heredoc) {
      const chunks: string[] = [];
      index += 1;
      while (index < lines.length && lines[index] !== "EOF") {
        chunks.push(lines[index] || "");
        index += 1;
      }
      data[heredoc[1] as keyof DiagnosticsData] = chunks.join("\n").trim();
      continue;
    }

    const line = lines[index] || "";
    const eq = line.indexOf("=");
    if (eq > 0) {
      const key = line.slice(0, eq) as keyof DiagnosticsData;
      data[key] = line.slice(eq + 1);
    }
  }

  return data;
}
