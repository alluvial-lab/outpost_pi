import { stdout } from "node:process";

/** Provide clipboard writes without coupling command-surface code to a platform API. */
export interface ClipboardPort {
  /** Copy exact text to the operator's clipboard. */
  copy(text: string): Promise<void>;
}

/** Write terminal clipboard control sequences for OSC 52-capable terminals. */
export class Osc52Clipboard implements ClipboardPort {
  constructor(private readonly write: (sequence: string) => void = (sequence) => {
    stdout.write(sequence);
  }) {}

  /** Copy text through the terminal's OSC 52 clipboard escape sequence. */
  async copy(text: string): Promise<void> {
    const encoded = Buffer.from(text, "utf8").toString("base64");
    this.write(`\x1b]52;c;${encoded}\x07`);
  }
}
