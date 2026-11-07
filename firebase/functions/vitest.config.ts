import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // The emulator suites share one Firestore, so files run one after another.
    fileParallelism: false,
    testTimeout: 20_000,
  },
});
