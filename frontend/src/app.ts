import { AUTO_REFRESH_MS, FORCE_STOP_CMD, MIN_REFRESH_FEEDBACK_MS, REPAIR_CMD, STATUS_CMD } from "./constants";
import { parseStatusOutput, wait } from "./diagnostics";
import { getById } from "./dom";
import { execCommand, toast } from "./ksu";
import { DiagnosticsRenderer } from "./renderer";
import { SerialTaskQueue } from "./serial-task-queue";
import type { LogTabName } from "./types";

export class DiagnosticsApp {
  private autoRefreshTimer: number | null = null;
  private refreshPromise: Promise<void> | null = null;
  private refreshRequested = false;
  private readonly renderer = new DiagnosticsRenderer();
  private readonly queue = new SerialTaskQueue();

  init(): void {
    getById<HTMLButtonElement>("refresh").addEventListener("click", () => {
      void this.requestRefresh();
    });
    getById<HTMLButtonElement>("run-fix").addEventListener("click", () => {
      void this.queue.run(() => this.performFix());
    });
    getById<HTMLButtonElement>("force-stop").addEventListener("click", () => {
      void this.queue.run(() => this.performForceStopTikTok());
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
        void this.requestRefresh();
      }
    });

    this.syncAutoRefresh();
    this.renderer.setRefreshState("idle");
    void this.requestRefresh();
  }

  private requestRefresh(): Promise<void> {
    this.refreshRequested = true;

    if (this.refreshPromise) {
      return this.refreshPromise;
    }

    this.refreshPromise = this.queue.run(async () => {
      try {
        while (this.refreshRequested) {
          this.refreshRequested = false;
          await this.performRefresh();
        }
      } finally {
        this.refreshPromise = null;
      }
    });

    return this.refreshPromise;
  }

  private async performRefresh(): Promise<void> {
    this.renderer.setBusy(true);
    this.renderer.setRefreshState("loading");

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

  private async performFix(): Promise<void> {
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
      await this.performRefresh();
      toast(result.errno === 0 ? "Repair completed" : "Repair failed");
    } catch (error) {
      const message = error instanceof Error ? error.stack || error.message : String(error);
      this.renderer.updateCommandOutput(message);
      toast("Repair failed");
    } finally {
      this.renderer.setBusy(false);
    }
  }

  private async performForceStopTikTok(): Promise<void> {
    this.renderer.setBusy(true);
    this.renderer.updateCommandOutput("Force-stopping TikTok...");

    try {
      const result = await execCommand(FORCE_STOP_CMD, {}, 5000);
      this.renderer.updateCommandOutput(result.stderr || "TikTok force-stopped.");
      await this.performRefresh();
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
      void this.requestRefresh();
    }, AUTO_REFRESH_MS);
  }
}
