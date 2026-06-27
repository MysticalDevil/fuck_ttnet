export class SerialTaskQueue {
  private tail: Promise<void> = Promise.resolve();

  run(task: () => Promise<void>): Promise<void> {
    const nextTask = this.tail.then(task, task);
    this.tail = nextTask.catch(() => undefined);
    return nextTask;
  }
}
