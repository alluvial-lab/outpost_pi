/**
 * Fallback model registry shared by action handlers when no live session
 * context is available.
 *
 * Pi 0.84 exposes `ModelRuntime` as the canonical SDK model/auth owner and
 * keeps `ModelRegistry` as the synchronous extension-facing facade. Normal
 * actions prefer `ctx.modelRegistry` so extension-registered providers remain
 * visible; this lazily-created runtime covers the brief lifecycle windows in
 * which no session context is bound.
 */

import { ModelRegistry, ModelRuntime } from "@earendil-works/pi-coding-agent";

let _registry: Promise<ModelRegistry> | null = null;

/** Lazily create and cache the SDK's asynchronous model runtime and registry facade. */
export function ensureModelRegistry(): Promise<ModelRegistry> {
  if (_registry) return _registry;

  const pending = ModelRuntime.create().then((runtime) => new ModelRegistry(runtime));
  _registry = pending;
  void pending.catch(() => {
    if (_registry === pending) _registry = null;
  });
  return pending;
}

/** Test seam — drop the cached registry so tests can rebuild with fakes. */
export function _resetModelRegistryForTests(): void {
  _registry = null;
}
