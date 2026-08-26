import { ImageResponse } from "next/og";

import { constellationMark } from "@/generated/constellation_mark.generated";

export const alt = "Outpost-Pi — Your coding agents, in your pocket";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

/** Generate the branded Open Graph image for shared links. */
export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "row",
          alignItems: "center",
          justifyContent: "center",
          gap: 64,
          backgroundColor: "#0D1210",
          backgroundImage:
            "radial-gradient(circle at 80% 20%, rgba(116,204,156,0.18), transparent 60%)",
          padding: 80,
          fontFamily: "monospace",
        }}
      >
        <div
          style={{
            display: "flex",
            width: 280,
            height: 280,
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <svg width="280" height="280" viewBox={constellationMark.viewBox}>
            <rect width="1024" height="1024" fill="#0D1210" rx="200" />
            <path
              d={constellationMark.edgePath}
              stroke={constellationMark.ink}
              strokeWidth={constellationMark.strokeWidth}
              strokeLinecap={constellationMark.strokeLinecap}
            />
            <rect
              x={constellationMark.hub.x}
              y={constellationMark.hub.y}
              width={constellationMark.hub.width}
              height={constellationMark.hub.height}
              rx={constellationMark.hub.radius}
              fill={constellationMark.accent}
            />
            <circle
              cx={constellationMark.peers[0].cx}
              cy={constellationMark.peers[0].cy}
              r={constellationMark.peers[0].radius}
              fill={constellationMark.ink}
            />
            <circle
              cx={constellationMark.peers[1].cx}
              cy={constellationMark.peers[1].cy}
              r={constellationMark.peers[1].radius}
              fill={constellationMark.ink}
            />
          </svg>
        </div>
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 20,
            maxWidth: 640,
          }}
        >
          <div
            style={{
              fontSize: 28,
              color: "#74CC9C",
              letterSpacing: 4,
              fontWeight: 700,
            }}
          >
            outpost_pi
          </div>
          <div
            style={{
              fontSize: 64,
              color: "#E4EFE8",
              fontWeight: 700,
              lineHeight: 1.1,
            }}
          >
            Your coding agents, in your pocket.
          </div>
          <div
            style={{
              fontSize: 28,
              color: "#89978D",
              lineHeight: 1.4,
            }}
          >
            Phone gateway · always-on 24/7 · one mesh, any machine
          </div>
        </div>
      </div>
    ),
    { ...size },
  );
}
