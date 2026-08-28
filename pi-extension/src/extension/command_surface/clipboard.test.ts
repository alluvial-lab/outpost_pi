import { describe, expect, test, vi } from "vitest";
import { Osc52Clipboard, type ClipboardPort } from "./clipboard.js";
import { PairingCodeDialog } from "./pairing_coordinator.js";

describe("Osc52Clipboard", () => {
  test("writes the exact UTF-8 text in an OSC 52 sequence", async () => {
    const write = vi.fn();
    const clipboard = new Osc52Clipboard(write);
    const text = "outpostpi://pair?epk=uj0Hdg8%3D&room=83MK60khBrcQ";

    await clipboard.copy(text);

    expect(write).toHaveBeenCalledOnce();
    expect(write).toHaveBeenCalledWith(
      `\x1b]52;c;${Buffer.from(text, "utf8").toString("base64")}\x07`,
    );
  });
});

describe("PairingCodeDialog clipboard action", () => {
  const theme = {
    accent: (text: string) => text,
    dim: (text: string) => text,
  };

  test("copies the exact URI on c and shows confirmation feedback", async () => {
    const uri = "https://outpost-pi.kevoun.com/pair#t=uj0Hdg8%3D&room=83MK60khBrcQ";
    const copy = vi.fn<ClipboardPort["copy"]>(() => Promise.resolve());
    const tui = { requestRender: vi.fn() };
    const dialog = new PairingCodeDialog(
      "QR",
      uri,
      Date.now() + 60_000,
      theme,
      tui,
      { copy },
      vi.fn(),
    );

    expect(dialog.render(200)).toContain("Press c to copy pairing code.");

    dialog.handleInput("c");
    await Promise.resolve();
    await Promise.resolve();

    expect(copy).toHaveBeenCalledOnce();
    expect(copy).toHaveBeenCalledWith(uri);
    expect(dialog.render(200)).toContain("Pairing code copied to clipboard.");
    expect(tui.requestRender).toHaveBeenCalledTimes(2);
  });
});
