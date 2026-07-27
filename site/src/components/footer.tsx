import Link from "next/link";

const GITHUB_URL = "https://github.com/alluvial-lab/outpost_pi";

/** Render the shared site footer and external resource links. */
export function SiteFooter() {
  return (
    <footer className="footer">
      <div className="wrap footer-inner">
        <div className="copy">
          © {new Date().getFullYear()} <b>Outpost-Pi</b>. Open source under
          the MIT license.
        </div>
        <nav className="footer-links">
          <Link href="/cockpit">Cockpit</Link>
          <Link href="/download">Download</Link>
          <Link href="/terms">Terms of Service</Link>
          <Link href="/privacy">Privacy Policy</Link>
          <a
            href={`${GITHUB_URL}/blob/main/PROTOCOL.md`}
            target="_blank"
            rel="noopener noreferrer"
          >
            Protocol
          </a>
          <a href={GITHUB_URL} target="_blank" rel="noopener noreferrer">
            GitHub
          </a>
        </nav>
      </div>
    </footer>
  );
}
