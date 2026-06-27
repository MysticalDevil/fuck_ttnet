import assert from "node:assert/strict";
import test from "node:test";

import { SerialTaskQueue } from "./serial-task-queue.ts";

test("runs queued tasks sequentially", async () => {
  const queue = new SerialTaskQueue();
  const order: string[] = [];
  let releaseFirstTask!: () => void;
  const firstGate = new Promise<void>((resolve) => {
    releaseFirstTask = resolve;
  });

  const firstTask = queue.run(async () => {
    order.push("first-start");
    await firstGate;
    order.push("first-end");
  });

  const secondTask = queue.run(async () => {
    order.push("second-start");
    order.push("second-end");
  });

  await Promise.resolve();
  await Promise.resolve();
  assert.deepEqual(order, ["first-start"]);

  releaseFirstTask();
  await Promise.all([firstTask, secondTask]);

  assert.deepEqual(order, [
    "first-start",
    "first-end",
    "second-start",
    "second-end",
  ]);
});

test("keeps the queue usable after a failure", async () => {
  const queue = new SerialTaskQueue();
  const order: string[] = [];

  await assert.rejects(
    queue.run(async () => {
      order.push("failed-task");
      throw new Error("boom");
    }),
    /boom/,
  );

  await queue.run(async () => {
    order.push("recovery-task");
  });

  assert.deepEqual(order, ["failed-task", "recovery-task"]);
});
