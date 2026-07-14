import { beforeEach, describe, expect, test, vi } from "vitest";

const { readConfig } = vi.hoisted(() => ({ readConfig: vi.fn() }));

vi.mock("node:fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs")>();
  return {
    ...actual,
    default: { ...actual, readFileSync: readConfig },
  };
});

import {
  isValidRelayUrl,
  isWebSocketScheme,
  resolveRelayUrl,
  toWebSocketUrl,
  toHttpUrl,
} from "./config.js";

beforeEach(() => {
  delete process.env["OUTPOST_PI_RELAY"];
  readConfig.mockReset();
  readConfig.mockImplementation(() => { throw new Error("config not found"); });
});

describe("isValidRelayUrl (strict http(s):// only)", () => {
  test("accepts http://", () => {
    expect(isValidRelayUrl("http://foo.test")).toBe(true);
    expect(isValidRelayUrl("http://foo.test:3000")).toBe(true);
    expect(isValidRelayUrl("http://192.168.1.10:3000")).toBe(true);
  });

  test("accepts https://", () => {
    expect(isValidRelayUrl("https://relay.example.tld")).toBe(true);
    expect(isValidRelayUrl("https://relay.example.tld:3000")).toBe(true);
  });

  test("rejects ws:// (user must use http:// + auto-convert)", () => {
    expect(isValidRelayUrl("ws://foo.test")).toBe(false);
    expect(isValidRelayUrl("ws://192.168.1.10:3000")).toBe(false);
  });

  test("rejects wss:// (user must use https:// + auto-convert)", () => {
    expect(isValidRelayUrl("wss://relay.example.tld")).toBe(false);
  });

  test("rejects empty / non-URL / non-http scheme", () => {
    expect(isValidRelayUrl("")).toBe(false);
    expect(isValidRelayUrl("not a url")).toBe(false);
    expect(isValidRelayUrl("ftp://example.tld")).toBe(false);
    expect(isValidRelayUrl("file:///etc/passwd")).toBe(false);
  });
});

describe("isWebSocketScheme", () => {
  test("true for ws:// and wss://", () => {
    expect(isWebSocketScheme("ws://foo")).toBe(true);
    expect(isWebSocketScheme("wss://foo")).toBe(true);
    expect(isWebSocketScheme("WSS://Foo")).toBe(true); // case-insensitive
  });

  test("false for http://, https://, and others", () => {
    expect(isWebSocketScheme("http://foo")).toBe(false);
    expect(isWebSocketScheme("https://foo")).toBe(false);
    expect(isWebSocketScheme("ftp://foo")).toBe(false);
    expect(isWebSocketScheme("")).toBe(false);
  });
});

describe("toWebSocketUrl (http(s):// → ws(s)://)", () => {
  test("https:// → wss://", () => {
    expect(toWebSocketUrl("https://relay.example.tld")).toBe("wss://relay.example.tld");
    expect(toWebSocketUrl("https://foo:3000/path")).toBe("wss://foo:3000/path");
  });

  test("http:// → ws://", () => {
    expect(toWebSocketUrl("http://relay.example.tld")).toBe("ws://relay.example.tld");
    expect(toWebSocketUrl("http://192.168.1.10:3000")).toBe("ws://192.168.1.10:3000");
  });

  test("ws(s):// pass through (defensive — env override may bypass validation)", () => {
    expect(toWebSocketUrl("ws://foo")).toBe("ws://foo");
    expect(toWebSocketUrl("wss://foo")).toBe("wss://foo");
  });

  test("case-insensitive scheme match", () => {
    expect(toWebSocketUrl("HTTPS://Foo")).toBe("wss://Foo");
    expect(toWebSocketUrl("HTTP://Foo")).toBe("ws://Foo");
  });
});

describe("toHttpUrl (ws(s):// → http(s)://)", () => {
  test("wss:// → https://", () => {
    expect(toHttpUrl("wss://relay.example.tld")).toBe("https://relay.example.tld");
  });

  test("ws:// → http://", () => {
    expect(toHttpUrl("ws://192.168.1.10:3000")).toBe("http://192.168.1.10:3000");
  });

  test("http(s):// pass through", () => {
    expect(toHttpUrl("https://foo")).toBe("https://foo");
    expect(toHttpUrl("http://foo:3000")).toBe("http://foo:3000");
  });
});

describe("resolveRelayUrl", () => {
  test("reports unconfigured when neither environment nor config supplies a relay", () => {
    expect(resolveRelayUrl()).toEqual({ url: null, source: "unconfigured" });
  });

  test("uses and canonicalizes the configured relay", () => {
    readConfig.mockReturnValue(JSON.stringify({ relay: "ws://config.example.test" }));

    expect(resolveRelayUrl()).toEqual({ url: "http://config.example.test", source: "config" });
  });

  test("uses and canonicalizes the environment relay ahead of config", () => {
    readConfig.mockReturnValue(JSON.stringify({ relay: "https://config.example.test" }));
    process.env["OUTPOST_PI_RELAY"] = "wss://env.example.test";

    expect(resolveRelayUrl()).toEqual({ url: "https://env.example.test", source: "env" });
  });
});
