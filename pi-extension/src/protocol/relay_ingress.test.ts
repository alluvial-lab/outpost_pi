import { describe, expect, test } from "vitest";
import {
  decodeRelayChallenge,
  decodeRelayIngress,
  RelayIngressDecodeError,
} from "./relay_ingress.js";

function outer(payload: Buffer, overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    peer: "owner-a",
    room: "main",
    ct: payload.toString("base64"),
    ...overrides,
  });
}

describe("relay ingress boundary", () => {
  test("decodes typed outer, generated control, and generated cross-PC frames", () => {
    expect(decodeRelayIngress(outer(Buffer.from("hello")))).toMatchObject({
      kind: "outer",
      frame: { peer: "owner-a", room: "main" },
      payloadUtf8: "hello",
    });
    expect(decodeRelayIngress(JSON.stringify({
      type: "presence",
      states: [{ peer: "pi-a", online: true, since_ts: null }],
    }))).toMatchObject({ kind: "control", frame: { type: "presence" } });
    expect(decodeRelayIngress(JSON.stringify({
      type: "pi_envelope_in",
      from_pc: "pi-a",
      to_room: "main",
      envelope: { from: "a:sess", to: "b:agent", id: "id-1", re: null, body: {} },
    }))).toMatchObject({ kind: "cross_pc", frame: { type: "pi_envelope_in" } });
  });

  test("rejects raw oversize before malformed JSON parsing", () => {
    expect(() => decodeRelayIngress("not json", { maxRawBytes: 3 })).toThrowError(
      expect.objectContaining<Partial<RelayIngressDecodeError>>({ code: "too_large" }),
    );
  });

  test("checks encoded length before decode and accepts the exact decoded boundary", () => {
    expect(decodeRelayIngress(outer(Buffer.from([1, 2, 3])), {
      maxRawBytes: 1024,
      maxDecodedPayloadBytes: 3,
    })).toMatchObject({ kind: "outer" });

    expect(() => decodeRelayIngress(outer(Buffer.from([1, 2, 3, 4])), {
      maxRawBytes: 1024,
      maxDecodedPayloadBytes: 3,
    })).toThrowError(expect.objectContaining<Partial<RelayIngressDecodeError>>({ code: "too_large" }));
  });

  test("accepts only a canonical 32-byte bounded auth challenge", () => {
    const nonce = Buffer.alloc(32, 7).toString("base64");
    expect(decodeRelayChallenge(JSON.stringify({ type: "challenge", nonce }))).toEqual({
      type: "challenge",
      nonce,
    });
    expect(() => decodeRelayChallenge(JSON.stringify({
      type: "challenge",
      nonce: Buffer.alloc(31).toString("base64"),
    }))).toThrowError(expect.objectContaining<Partial<RelayIngressDecodeError>>({
      code: "invalid_message",
    }));
  });

  test("rejects malformed generated control and cross-PC shapes", () => {
    for (const frame of [
      { type: "presence", states: [{ peer: "pi-a", online: "yes" }] },
      { type: "rooms", peer: "pi-a", rooms: [{ room_id: "main" }] },
      { type: "pi_envelope_in", from_pc: "pi-a", to_room: "", envelope: {} },
    ]) {
      expect(() => decodeRelayIngress(JSON.stringify(frame))).toThrowError(
        expect.objectContaining<Partial<RelayIngressDecodeError>>({ code: "unsupported_type" }),
      );
    }
  });
});
