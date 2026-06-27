import type { ExecResult } from "./types";

export function execCommand(
  command: string,
  options: Record<string, unknown> = {},
  timeoutMs = 10000,
): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    if (!window.ksu || typeof window.ksu.exec !== "function") {
      reject(new Error("KernelSU WebUI API is not available"));
      return;
    }

    const callbackName = `fuck_ttnet_exec_${Date.now()}_${Math.random()
      .toString(16)
      .slice(2)}`;

    const timeout = window.setTimeout(() => {
      delete window[callbackName];
      reject(new Error(`Command timed out after ${timeoutMs} ms: ${command}`));
    }, timeoutMs);

    window[callbackName] = (errno: number, stdout: string, stderr: string) => {
      window.clearTimeout(timeout);
      delete window[callbackName];
      resolve({ errno, stdout, stderr });
    };

    try {
      window.ksu.exec(command, JSON.stringify(options), callbackName);
    } catch (error) {
      window.clearTimeout(timeout);
      delete window[callbackName];
      reject(error);
    }
  });
}

export function toast(message: string): void {
  window.ksu?.toast?.(message);
}
