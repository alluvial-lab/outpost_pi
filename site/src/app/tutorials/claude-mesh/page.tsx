import type { Metadata } from "next";
import Link from "next/link";
import { DocsSection, DocsSubsection, InlineCode } from "@/components/docs-shell";
import { CodeBlock } from "@/components/code-block";
import { Callout } from "@/components/callout";
import { Pager } from "@/components/pager";
import { RevealController } from "@/components/landing/reveal-controller";

export const metadata: Metadata = {
  title: "Claude in the mesh",
  description:
    "Advanced extra: outpost-pi claude puts Claude Code on the agent mesh as a named peer next to Pi — agent-to-agent, driven from the terminal. Not in the app yet.",
};

/** Render the advanced Claude Code mesh tutorial. */
export default function ClaudeMeshTutorial() {
  return (
    <div className="page">
      <div className="page-body">
        <div className="wrap">
          <div className="tut">
            <header className="page-head reveal" style={{ maxWidth: "none" }}>
              <div className="flex flex-wrap items-center gap-3">
                <span className="inline-flex items-center rounded-full border border-accent/40 bg-accent/15 px-3 py-1 text-xs font-semibold uppercase tracking-[0.15em] text-accent">
                  Extra · terminal only — no app yet
                </span>
              </div>
              <span className="eyebrow" style={{ marginTop: 14 }}>
                Tutorial · Extra
              </span>
              <h1>Claude in the mesh</h1>
              <p className="lede">
                <InlineCode>outpost-pi claude</InlineCode> puts{" "}
                <strong className="text-fg">Claude Code</strong> on the same
                agent mesh as Pi — a named peer on the local UDS broker and,
                through the relay, across PCs. This is an advanced,
                agent-to-agent setup driven entirely from the terminal. It is{" "}
                <strong className="text-fg">
                  not surfaced in the mobile app yet
                </strong>{" "}
                — see <a href="#no-app">why</a> at the end.
              </p>
            </header>

            <article className="prose">
              <DocsSection id="prereqs" title="Before you start">
          <ul className="ml-6 list-disc space-y-2">
            <li>
              The <InlineCode>outpost-pi</InlineCode> CLI on your{" "}
              <InlineCode>$PATH</InlineCode> — run{" "}
              <InlineCode>/outpost-pi install</InlineCode> once (see the{" "}
              <Link href="/tutorials/daemon" className="text-accent underline">
                daemon tutorial
              </Link>
              ) to link it.
            </li>
            <li>
              <strong className="text-fg">Claude Code</strong> installed and on
              your <InlineCode>$PATH</InlineCode> as{" "}
              <InlineCode>claude</InlineCode>.
            </li>
            <li>
              A folder that <strong className="text-fg">isn&apos;t</strong>{" "}
              already running a Pi agent (see{" "}
              <a href="#cwd-lock" className="text-accent underline">
                one agent per folder
              </a>
              ).
            </li>
          </ul>
        </DocsSection>

        <DocsSection id="run" title="Run it">
          <CodeBlock
            code={`outpost-pi claude            # uses the current folder
outpost-pi claude ~/code/api  # or target a specific folder`}
            label="Shell"
            language="bash"
          />
          <p>
            On the first run in a folder, it asks for an agent name (defaulting
            to the folder name) and saves a small config:
          </p>
          <CodeBlock
            code={`[outpost-pi] No config found for /Users/you/code/api
Let's set up this agent.

Agent name [api]: reviewer`}
            label="First run"
            language="text"
          />
          <p>
            That name is how other agents address this Claude in{" "}
            <InlineCode>list_peers</InlineCode> and{" "}
            <InlineCode>agent_send</InlineCode>. Then it wires two things into
            Claude Code and launches it.
          </p>
        </DocsSection>

        <DocsSection id="injected" title="What it wires in">
          <p>
            <InlineCode>outpost-pi claude</InlineCode> is a wrapper. It wires
            two things into the Claude process it spawns, then runs{" "}
            <InlineCode>claude</InlineCode> in the target folder.
          </p>

          <DocsSubsection id="mcp" title="1. An MCP server (the mesh tools)">
            <p>
              It writes a throwaway MCP config — a temp file pointing at the
              packaged <InlineCode>mesh_server.js</InlineCode> — and hands it
              to Claude for this one process via{" "}
              <InlineCode>--mcp-config</InlineCode>. Nothing is registered in{" "}
              <InlineCode>~/.claude.json</InlineCode>, nothing is written into
              the project folder, and the temp file is deleted when the session
              exits. (The wrapper also removes a legacy{" "}
              <InlineCode>outpost-pi-mesh</InlineCode> local-scope entry left
              by older versions, so a plain <InlineCode>claude</InlineCode> in
              the same folder never inherits the mesh by accident.)
            </p>
            <p>
              The server exposes three tools to Claude — the same mesh API Pi
              agents get:
            </p>
            <ul className="ml-6 list-disc space-y-2">
              <li>
                <InlineCode>list_peers</InlineCode> — who is online: local peers
                plus cross-PC ones in <InlineCode>pc_label:peer</InlineCode> form
                (e.g. <InlineCode>MacMini:backend</InlineCode>).
              </li>
              <li>
                <InlineCode>agent_send({`{ to, body, re? }`})</InlineCode> — send
                a message and get an <strong className="text-fg">ACK</strong> back
                (<InlineCode>received</InlineCode>, <InlineCode>denied</InlineCode>, or{" "}
                <InlineCode>timeout</InlineCode>). It is{" "}
                <strong className="text-fg">not fire-and-forget</strong>; set{" "}
                <InlineCode>re</InlineCode> to the id of the message you&apos;re
                replying to.
              </li>
              <li>
                <InlineCode>get_messages</InlineCode> — drain this agent&apos;s
                inbox of pending messages.
              </li>
            </ul>
          </DocsSubsection>

          <DocsSubsection id="skill" title="2. The agent-network skill">
            <p>
              An MCP server gives Claude the tools but not the{" "}
              <em className="text-fg">habits</em>. Skills load only from disk,
              so the wrapper appends the packaged agent-network skill to this
              session&apos;s system prompt (via{" "}
              <InlineCode>--append-system-prompt-file</InlineCode>) — nothing
              is deployed into <InlineCode>~/.claude/skills</InlineCode>, and
              unrelated Claude sessions are untouched. The skill teaches
              Claude to:
            </p>
            <ul className="ml-6 list-disc space-y-2">
              <li>
                call <InlineCode>get_messages</InlineCode> at the start of every
                turn, so incoming messages are seen promptly;
              </li>
              <li>
                read the <InlineCode>agent_send</InlineCode> ACK and act on it
                (<InlineCode>received</InlineCode> means delivered, give up on{" "}
                <InlineCode>denied</InlineCode>, investigate{" "}
                <InlineCode>timeout</InlineCode>) rather than assuming delivery;
              </li>
              <li>
                reply by echoing the original message id in{" "}
                <InlineCode>re</InlineCode>, so threads stay linked;
              </li>
              <li>
                treat <InlineCode>broadcast</InlineCode> as fire-and-forget — no
                per-recipient ACK.
              </li>
            </ul>
          </DocsSubsection>

          <DocsSubsection id="channels" title="Message delivery: polling by default">
            <p>
              When a message lands, the MCP server buffers it in this
              agent&apos;s inbox. Claude reads pending messages by calling{" "}
              <InlineCode>get_messages</InlineCode> — the skill has it do so at
              the start of every turn, so an incoming message is seen the next
              time you prompt it (turn-boundary polling). That is the default,
              and it needs no special flags.
            </p>
            <p>
              Immediate wake is an opt-in: launch with{" "}
              <InlineCode>--outpost-mesh-wake</InlineCode> (see below) and the
              server&apos;s channel notification{" "}
              <strong className="text-fg">wakes Claude</strong> right away —
              no prompt needed. A wake is edge-triggered and rate-capped: a
              burst or broadcast nudges once, not once per message, and the
              nudge itself carries no message body — <InlineCode>get_messages</InlineCode>{" "}
              stays the single authoritative way to read what arrived.
            </p>
          </DocsSubsection>
        </DocsSection>

        <DocsSection id="flags" title="Safe defaults, opt-in flags">
          <p>
            The wrapper launches Claude with its normal permission policy —
            Claude asks you before running tools, and mesh messages arrive via{" "}
            <InlineCode>get_messages</InlineCode> polling. Two distinct opt-ins
            change that, and the wrapper only ever manages the second for you:
          </p>
          <ul className="list-disc pl-6 space-y-1">
            <li>
              <strong className="text-fg">Authority</strong> —{" "}
              <InlineCode>--dangerously-skip-permissions</InlineCode>{" "}
              auto-approves every tool call. Pass it through yourself; the
              wrapper never injects it.
            </li>
            <li>
              <strong className="text-fg">Initiative</strong> —{" "}
              <InlineCode>--outpost-mesh-wake</InlineCode> lets mesh peers
              START turns on the session. The wrapper expands it to the
              development-channels flag (Claude asks one consent question at
              launch) and pre-approves the read-only{" "}
              <InlineCode>get_messages</InlineCode> drain so an unattended
              woken turn can read what woke it.
            </li>
          </ul>
          <CodeBlock
            code={"# wake only — woken turns still face the approval gate:\noutpost-pi claude ~/code/api --outpost-mesh-wake\n\n# both — unattended peer-driven turns:\noutpost-pi claude ~/code/api --outpost-mesh-wake --dangerously-skip-permissions"}
            label="Opt in (you type this)"
            language="bash"
          />
          <Callout variant="warning" title="Know what these flags do">
            <InlineCode>--dangerously-skip-permissions</InlineCode>{" "}
            <strong className="text-fg">auto-approves every tool call</strong>{" "}
            — Claude runs Bash, edits, and writes without prompting you, which is
            what makes unattended agent-to-agent work possible but also removes
            your approval gate. <InlineCode>--outpost-mesh-wake</InlineCode>{" "}
            changes <em className="text-fg">who can start a turn</em>: any
            LOCAL mesh peer, not just you (cross-PC messages only buffer for
            the next drain — remote-initiated turns stay opt-out). It keeps the permission policy intact —
            but combined with skip-permissions, a peer message can drive
            unattended tool execution. Only point this at folders and peers
            you trust — same posture as promoting a folder to a{" "}
            <Link href="/tutorials/daemon" className="text-accent underline">
              daemon
            </Link>
            .
          </Callout>
        </DocsSection>

        <DocsSection id="cwd-lock" title="One agent per folder">
          <p>
            A kernel-enforced lock (the same one{" "}
            <InlineCode>/outpost-pi</InlineCode> takes) allows{" "}
            <strong className="text-fg">one outpost-pi agent per folder</strong> —
            Pi <em className="text-fg">or</em> Claude, never both in the same
            directory. If a folder already has a Pi agent, start Claude in a
            different folder; both still meet in the same local mesh. A second
            agent in a locked folder is refused before it connects, so it never
            becomes a ghost peer.
          </p>
        </DocsSection>

        <DocsSection id="no-app" title="Why this isn't in the app yet">
          <p>
            The mobile app talks to the{" "}
            <strong className="text-fg">relay</strong>, and it sees only the Pi
            agent that paired it. It does not see local UDS peers — like a Claude
            joined with <InlineCode>outpost-pi claude</InlineCode> — so a
            mesh-mate Claude won&apos;t show up in your phone. Surfacing the full
            mesh in the app is future work; for now this is a terminal-driven,
            agent-to-agent feature. Relay traffic, where it&apos;s used, is
            encrypted in transit.
          </p>
          <p>
            To watch two agents talk on one machine, pair this with the{" "}
            <Link href="/tutorials/mesh-local" className="text-accent underline">
              local mesh
            </Link>{" "}
            tutorial — start one peer as Pi and another as Claude, in two
            folders, and have them message each other.
          </p>
        </DocsSection>

            </article>

            <Pager
              prev={{ href: "/tutorials/daemon", label: "Daemon mode" }}
              next={{ href: "/tutorials", label: "All tutorials" }}
            />
          </div>
        </div>
      </div>
      <RevealController />
    </div>
  );
}
