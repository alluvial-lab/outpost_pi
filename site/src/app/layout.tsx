import type { Metadata } from "next";
import { Space_Mono } from "next/font/google";
import "./globals.css";
import { SiteHeader } from "@/components/header";
import { SiteFooter } from "@/components/footer";

const spaceMono = Space_Mono({
  variable: "--font-space-mono",
  subsets: ["latin"],
  weight: ["400", "700"],
  style: ["normal", "italic"],
  display: "swap",
});

const siteTagline = "Outpost-Pi — Your coding agents, in your pocket";
const siteDescription =
  "Pair your phone once, then drive any Pi coding agent from it — keep a fleet running 24/7 and link every machine into one mesh. Open source, self-hostable.";

export const metadata: Metadata = {
  metadataBase: new URL("https://outpost-pi.kevoun.com"),
  title: {
    default: siteTagline,
    template: "%s · Outpost-Pi",
  },
  description: siteDescription,
  applicationName: "Outpost-Pi",
  authors: [{ name: "Outpost-Pi", url: "https://github.com/alluvial-lab/outpost_pi" }],
  keywords: [
    "Outpost-Pi",
    "coding agents",
    "Pi coding agent",
    "mobile agent control",
    "24/7 agent daemon",
    "agent mesh",
    "self-hostable relay",
  ],
  openGraph: {
    type: "website",
    url: "https://outpost-pi.kevoun.com",
    title: siteTagline,
    description: siteDescription,
    siteName: "Outpost-Pi",
  },
  twitter: {
    card: "summary_large_image",
    title: siteTagline,
    description: siteDescription,
  },
};

/** Render the shared document shell, navigation, and footer. */
export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${spaceMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col bg-bg text-fg">
        <div className="app flex min-h-full flex-1 flex-col" id="top">
          <SiteHeader />
          <main className="flex-1">{children}</main>
          <SiteFooter />
        </div>
      </body>
    </html>
  );
}
