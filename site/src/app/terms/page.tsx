import type { Metadata } from "next";
import { LegalShell, LegalSection } from "@/components/legal-shell";

const GITHUB_URL = "https://github.com/alluvial-lab/outpost_pi";

export const metadata: Metadata = {
  title: "Terms of Service",
  description:
    "Terms for using the self-hosted Outpost-Pi open-source software.",
};

/** Render the project's terms of service. */
export default function TermsPage() {
  return (
    <LegalShell
      title="Terms of Service"
      lastUpdated="2026-07-14"
      subtitle={
        <p>
          Outpost-Pi is an open-source project. These terms describe use of the
          project software; they do not provide a hosted relay service.
        </p>
      }
    >
      <LegalSection id="acceptance" number={1} title="Using Outpost-Pi">
        <p>
          By installing or using the Outpost-Pi mobile application, Pi-side
          extension, relay source, or related project software, you agree to use
          it lawfully and responsibly. If you do not agree, do not use the
          software.
        </p>
        <p>
          Outpost-Pi does not require an account or email registration. Pairing
          is established locally between your devices with cryptographic keys.
          You are responsible for protecting those devices and revoking a
          pairing when it is no longer trusted.
        </p>
      </LegalSection>

      <LegalSection id="relay" number={2} title="Your self-hosted relay">
        <p>
          Outpost-Pi is local-relay-only. Build and run the relay from the
          project&apos;s <code>relay/</code> source on infrastructure you control,
          then configure your devices to use that relay. The project does not
          operate a shared relay.
        </p>
        <p>
          You are responsible for your relay&apos;s availability, server security,
          network restrictions, backups, logging, retention, and compliance with
          laws that apply to your deployment. Do not configure a relay unless you
          are authorized to operate it and the network it uses.
        </p>
      </LegalSection>

      <LegalSection id="content" number={3} title="Your content and security">
        <p>
          Prompts sent to your Pi-side agent and the responses it produces are
          your content. The relay source forwards those payloads, but
          application-layer end-to-end encryption is not active in the current
          MVP. A relay administrator could access plaintext in memory while
          forwarding it.
        </p>
        <p>
          Use a relay you control, protect administrative access, and place it
          behind a VPN or equivalent network restriction when your threat model
          requires it. You remain responsible for the content you send and for
          any third-party terms that apply to your coding-agent or model
          provider.
        </p>
      </LegalSection>

      <LegalSection id="conduct" number={4} title="Acceptable use">
        <p>You must not:</p>
        <ul className="ml-6 list-disc space-y-2">
          <li>
            Attempt to bypass or weaken the pairing and transport security used
            by the software, or impersonate another paired device.
          </li>
          <li>
            Use the software or your relay deployment to attack, overload, or
            disrupt systems or networks.
          </li>
          <li>
            Use the software to facilitate unlawful activity or violate the
            rights of another person or organization.
          </li>
        </ul>
      </LegalSection>

      <LegalSection id="availability" number={5} title="Availability and warranties">
        <p>
          The software is provided on an &quot;as is&quot; and &quot;as available&quot;
          basis. Project maintainers do not guarantee uninterrupted operation,
          error-free behavior, or the availability of your self-hosted relay.
          You are responsible for monitoring and maintaining your deployment.
        </p>
      </LegalSection>

      <LegalSection id="license" number={6} title="License and project identity">
        <p>
          The source code is released under the MIT license in the project
          repository. Subject to that license, you may use, copy, modify, and
          distribute the source code. Review the repository&apos;s license and
          notices before redistributing the project or its assets.
        </p>
      </LegalSection>

      <LegalSection id="updates" number={7} title="Changes and contact">
        <p>
          The project may update these terms as the software changes. The
          current version is published on this site. For questions or to report
          a security issue, open an issue in the{" "}
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
