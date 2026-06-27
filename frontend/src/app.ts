import { AUTO_REFRESH_MS, FORCE_STOP_CMD, MIN_REFRESH_FEEDBACK_MS, REPAIR_CMD, STATUS_CMD } from "./constants";
import { parseStatusOutput, wait } from "./diagnostics";
import { getById } from "./dom";
import { execCommand, toast } from "./ksu";
import { DiagnosticsRenderer } from "./renderer";
import type { LogTabName } from "./types";

export class DiagnosticsApp {
  private autoRefreshTimer: number | null = null;
  private readonly renderer = new DiagnosticsRenderer();

  init(): void {
    getById<HTMLButtonElement>("refresh").addEventListener("click", () => {
      void this.refresh();
    });
    getById<HTMLButtonElement>("run-fix").addEventListener("click", () => {
      void this.runFix();
    });
    getById<HTMLButtonElement>("force-stop").addEventListener("click", () => {
      void this.forceStopTikTok();
    });
    getById<HTMLButtonElement>("copy-diagnostics").addEventListener("click", () => {
      void this.copyDiagnostics();
    });
    getById<HTMLInputElement>("auto-refresh").addEventListener("change", () => {
      this.syncAutoRefresh();
    });

    document.querySelectorAll<HTMLButtonElement>(".log-tab").forEach((button) => {
      button.addEventListener("click", () => {
        this.renderer.setActiveLogTab(button.dataset.logTab as LogTabName);
      });
    });

    document.addEventListener("visibilitychange", () => {
      if (!document.hidden && getById<HTMLInputElement>("auto-refresh").checked) {
        void this.refresh();
      }
    });

    this.syncAutoRefresh();
    this.renderer.setRefreshState("idle");
    void this.refresh();
  }

  async refresh(): Promise<void> {
    this.renderer.setBusy(true);
    this.renderer.setRefreshState("loading");
    this.renderer.updateCommandOutput("Running status check...");

    try {
      const [result] = await Promise.all([
        execCommand(STATUS_CMD, {}, 8000),
        wait(MIN_REFRESH_FEEDBACK_MS),
      ]);
      if (result.errno !== 0) {
        throw new Error(result.stderr || `status.sh exited ${result.errno}`);
      }

      const data = parseStatusOutput(result.stdout);
      this.renderer.render(data);
      this.renderer.setRefreshState("success");
      this.renderer.updateCommandOutput("Status refreshed.");
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.renderer.showError(message);
      this.renderer.setRefreshState("error", message);
      this.renderer.updateCommandOutput(
        error instanceof Error ? error.stack || message : message,
      );
      toast("Status check failed");
    } finally {
      this.renderer.setBusy(false);
    }
  }

  private async runFix(): Promise<void> {
    if (getById<HTMLButtonElement>("run-fix").dataset.repairable !== "yes") {
      toast("No local repair for this diagnosis");
      return;
    }

    this.renderer.setBusy(true);
    this.renderer.updateCommandOutput("Running diagnosis-specific repair...");

    try {
      const result = await execCommand(REPAIR_CMD, {}, 15000);
      this.renderer.updateCommandOutput(
        `${result.stdout}${result.stderr}`.trim() || "Repair command finished.",
      );
      await this.refresh();
      toast(result.errno === 0 ? "Repair completed" : "Repair failed");
    } catch (error) {
      const message = error instanceof Error ? error.stack || error.message : String(error);
      this.renderer.updateCommandOutput(message);
      toast("Repair failed");
    } finally {
      this.renderer.setBusy(false);
    }
  }

  private async forceStopTikTok(): Promise<void> {
    this.renderer.setBusy(true);
    this.renderer.updateCommandOutput("Force-stopping TikTok...");

    try {
      const result = await execCommand(FORCE_STOP_CMD, {}, 5000);
      this.renderer.updateCommandOutput(result.stderr || "TikTok force-stopped.");
      await this.refresh();
      toast(result.errno === 0 ? "TikTok stopped" : "Force stop failed");
    } catch (error) {
      const message = error instanceof Error ? error.stack || error.message : String(error);
      this.renderer.updateCommandOutput(message);
      toast("Force stop failed");
    } finally {
      this.renderer.setBusy(false);
    }
  }

  private async copyDiagnostics(): Promise<void> {
    if (!this.renderer.hasDiagnostics()) {
      toast("No diagnostics yet");
      return;
    }

    const textValue = this.renderer.getCopyPayload();

    try {
      await navigator.clipboard.writeText(textValue);
      toast("Diagnostics copied");
      this.renderer.updateCommandOutput("Diagnostics copied to clipboard.");
    } catch {
      this.renderer.updateCommandOutput(textValue);
      toast("Clipboard unavailable; diagnostics shown below");
    }
  }

  private syncAutoRefresh(): void {
    if (this.autoRefreshTimer != null) {
      window.clearInterval(this.autoRefreshTimer);
      this.autoRefreshTimer = null;
    }

    if (!getById<HTMLInputElement>("auto-refresh").checked) {
      return;
    }

    this.autoRefreshTimer = window.setInterval(() => {
      if (document.hidden) {
        return;
      }
      void this.refresh();
    }, AUTO_REFRESH_MS);
  }
}
