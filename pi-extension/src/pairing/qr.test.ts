import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const crypto = vi.hoisted(() => ({
  timingSafeEqual: vi.fn((left: Uint8Array, right: Uint8Array) => Buffer.from(left).equals(Buffer.from(right))),
}));

vi.mock("node:crypto", async (importOriginal) => ({
  ...await importOriginal<typeof import("node:crypto")>(),
  timingSafeEqual: crypto.timingSafeEqual,
}));

import {
  QRSession,
  clampPairTtlMs,
  TOKEN_TTL_MS,
  PAIR_TTL_MIN_MS,
  PAIR_TTL_MAX_MS,
} from "./qr.js";
import { pairTokenId } from "../transport/secure_channel.js";

const tokenId = (token: string): Uint8Array => pairTokenId(token);

describe("clampPairTtlMs", () => {
  test("passes a value inside the range unchanged", () => {
    expect(clampPairTtlMs(120_000)).toBe(120_000);
  });
  test("clamps below the minimum", () => {
    expect(clampPairTtlMs(1_000)).toBe(PAIR_TTL_MIN_MS);
  });
  test("clamps above the maximum", () => {
    expect(clampPairTtlMs(9_999_999)).toBe(PAIR_TTL_MAX_MS);
  });
  test("non-finite (NaN / Infinity) falls back to the default", () => {
    expect(clampPairTtlMs(Number.NaN)).toBe(TOKEN_TTL_MS);
    expect(clampPairTtlMs(Number.POSITIVE_INFINITY)).toBe(TOKEN_TTL_MS);
  });
});

describe("QRSession.issueToken — ttl", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  test("default ttl when none given", () => {
    vi.setSystemTime(new Date(1_000_000));
    const { expiresAt } = new QRSession().issueToken();
    expect(expiresAt).toBe(1_000_000 + TOKEN_TTL_MS);
  });

  test("honors a caller-supplied ttl", () => {
    vi.setSystemTime(new Date(1_000_000));
    const { expiresAt } = new QRSession().issueToken(120_000);
    expect(expiresAt).toBe(1_000_000 + 120_000);
  });

  test("expired token remains locator-resolvable until normal record replacement", () => {
    vi.setSystemTime(new Date(0));
    const s = new QRSession();
    const { token } = s.issueToken(10_000);
    vi.setSystemTime(new Date(10_001));
    expect(s.findTokenById(tokenId(token))).toBe(token);
    expect(s.consumeToken(token)).toBe("expired");
  });

  test("token-id lookup retains consumed status for a valid proof-holder", () => {
    vi.setSystemTime(new Date(0));
    const s = new QRSession();
    const { token } = s.issueToken(60_000);
    expect(s.findTokenById(tokenId(token))).toBe(token);
    expect(s.findTokenById(Uint8Array.from(Buffer.alloc(16, 7)))).toBeNull();
    expect(s.consumeToken(token)).toBe("ok");
    expect(s.findTokenById(tokenId(token))).toBe(token);
    expect(s.consumeToken(token)).toBe("consumed");
  });

  test("compares fixed-width locator bytes even when no token record exists", () => {
    const s = new QRSession();
    const { token } = s.issueToken(60_000);
    const issuedLocator = tokenId(token);
    crypto.timingSafeEqual.mockClear();

    expect(s.findTokenById(issuedLocator)).toBe(token);
    expect(crypto.timingSafeEqual).toHaveBeenLastCalledWith(issuedLocator, issuedLocator);

    s.clear();
    const absentLocator = Uint8Array.from(Buffer.alloc(16, 7));
    expect(s.findTokenById(absentLocator)).toBeNull();
    expect(crypto.timingSafeEqual).toHaveBeenLastCalledWith(absentLocator, expect.any(Uint8Array));
    expect(crypto.timingSafeEqual.mock.calls).toHaveLength(2);
  });

  test("issuing a new token invalidates the previous one", () => {
    vi.setSystemTime(new Date(0));
    const s = new QRSession();
    const first = s.issueToken(60_000).token;
    s.issueToken(60_000);
    expect(s.consumeToken(first)).toBe("unknown");
  });
});
