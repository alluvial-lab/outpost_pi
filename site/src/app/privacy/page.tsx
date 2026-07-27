import type { Metadata } from "next";
import { LegalShell, LegalSection } from "@/components/legal-shell";

const GITHUB_URL = "https://github.com/alluvial-lab/outpost_pi";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description:
    "Privacy Policy for Outpost-Pi — a self-hosted remote-coding project.",
};

/** Render the project's privacy policy. */
export default function PrivacyPage() {
  return (
    <LegalShell
      title="Privacy Policy"
      lastUpdated="2026-07-14"
      subtitle={
        <p>
          Outpost-Pi is open-source software. It does not provide or operate a
          shared relay; every relay deployment is run by its own operator.
        </p>
      }
    >
      <LegalSection id="scope" number={1} title="Scope">
        <p>
          This policy describes the Outpost-Pi website and the standard
          open-source software distribution. It does not cover a relay you run
          yourself or a relay run by another operator. That operator is
          responsible for its infrastructure, configuration, retention, and any
          privacy notices that apply to it.
        </p>
      </LegalSection>

      <LegalSection id="data" number={2} title="Data and relay deployments">
        <p>
          Outpost-Pi does not require an account, email registration, payment
          information, analytics, or tracking telemetry. Pairing keys are
          generated locally on your devices.
        </p>
        <p>
          The mobile app stores paired-peer information — public keys, a name
          you choose, and the relay URL — in platform secure storage (iOS
          Keychain or Android Keystore). This data remains on your device unless
          you send it to your own relay as part of normal operation.
        </p>
        <p>
          A self-hosted relay necessarily handles connection metadata and the
          encrypted-in-transit envelopes it forwards between paired devices. It
          also stores signed mesh-membership blobs in its configured database so
          devices restoring the same Owner key can recover their peer list.
          Configure retention, logging, backups, access controls, and any
          required notices for your deployment.
        </p>
        <p>
          Message payloads are not application-layer end-to-end encrypted in
          the current MVP. The included relay source forwards payloads rather
          than requiring them to be persisted, but a relay operator could access
          plaintext in memory while forwarding. Run the relay only on
          infrastructure you control and use a VPN or equivalent network
          restriction when appropriate.
        </p>
      </LegalSection>

      <LegalSection id="sharing" number={3} title="Sharing and transfers">
        <p>
          The project does not operate a centralized relay or receive relay
          traffic. Consequently, it does not share relay connection metadata or
          message payloads with third parties. Data handling and international
          transfers, if any, are determined by the operator and location of the
          relay you configure.
        </p>
      </LegalSection>

      <LegalSection id="security" number={4} title="Security and trust model">
        <p>
          Outpost-Pi uses TLS for relay connections and Ed25519
          challenge-response during pairing. These controls authenticate paired
          devices and protect traffic in transit, but they do not add
          application-layer end-to-end encryption to message payloads.
        </p>
        <p>
          Your relay&apos;s operator controls the server and can therefore affect
          its availability and privacy posture. Keep its database on persistent
          storage, protect administrative access, and restrict network reachability
          to the devices you intend to pair. See the project documentation for
          Docker and VPN deployment guidance.
        </p>
      </LegalSection>

      <LegalSection id="choices" number={5} title="Your choices">
        <p>
          You control whether to pair a device, which relay URL to configure,
          and when to revoke a pairing. You can remove paired peers from the app
          or extension and remove the data in your self-hosted relay according to
          your own operational procedures.
        </p>
      </LegalSection>

      <LegalSection id="updates" number={6} title="Policy updates and contact">
        <p>
          This policy may change as the project changes. The current version is
          published on this site. For project questions or to report a privacy
          concern in the software, open an issue in the{" "}
          <a
            className="text-accent underline"
            href={`${GITHUB_URL}/issues`}
            target="_blank"
            rel="noopener noreferrer"
          >
            Outpost-Pi repository
          </a>
          .
        </p>
      </LegalSection>
    </LegalShell>
  );
}
