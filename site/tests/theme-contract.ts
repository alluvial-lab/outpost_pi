import type { Page } from "@playwright/test";

export const DIRECT_THEME_ROLES = [
  "--color-bg-primary",
  "--color-bg-secondary",
  "--color-text-primary",
  "--color-text-secondary",
  "--brand-accent",
  "--color-on-accent",
] as const;

export type DirectThemeRole = (typeof DIRECT_THEME_ROLES)[number];
export type ThemeMode = "dark" | "light";
export type ThemeRoles = Record<DirectThemeRole, string>;

export type ThemePartition = {
  name: string;
  system: ThemeMode;
  forced: ThemeMode | null;
  expected: ThemeMode;
};

export const EXPECTED_THEME_ROLES: Record<ThemeMode, ThemeRoles> = {
  dark: {
    "--color-bg-primary": "#0d1210",
    "--color-bg-secondary": "#131a16",
    "--color-text-primary": "#e4efe8",
    "--color-text-secondary": "#89978d",
    "--brand-accent": "#74cc9c",
    "--color-on-accent": "#0a2418",
  },
  light: {
    "--color-bg-primary": "#f3f6f3",
    "--color-bg-secondary": "#f8faf8",
    "--color-text-primary": "#182019",
    "--color-text-secondary": "#57635a",
    "--brand-accent": "#256e47",
    "--color-on-accent": "#ffffff",
  },
};

export const THEME_PARTITIONS: readonly ThemePartition[] = [
  {
    name: "system dark without an override",
    system: "dark",
    forced: null,
    expected: "dark",
  },
  {
    name: "system light without an override",
    system: "light",
    forced: null,
    expected: "light",
  },
  {
    name: "system light with a forced dark override",
    system: "light",
    forced: "dark",
    expected: "dark",
  },
  {
    name: "system dark with a forced light override",
    system: "dark",
    forced: "light",
    expected: "light",
  },
];

export const WCAG_AA_NORMAL_TEXT_RATIO = 4.5;

export type ContrastPair = {
  foreground: DirectThemeRole;
  background: DirectThemeRole;
};

export const AA_CONTRAST_PAIRS: readonly ContrastPair[] = [
  {
    foreground: "--color-text-primary",
    background: "--color-bg-primary",
  },
  {
    foreground: "--color-text-secondary",
    background: "--color-bg-primary",
  },
  {
    foreground: "--brand-accent",
    background: "--color-bg-primary",
  },
  {
    foreground: "--color-on-accent",
    background: "--brand-accent",
  },
];

type RgbColor = readonly [red: number, green: number, blue: number];

type ProbeResult = {
  declared: string;
  color: string;
  backgroundColor: string;
};

/** Read direct semantic roles after the browser has resolved the CSS cascade. */
export async function readResolvedTheme(page: Page): Promise<ThemeRoles> {
  const probeResults = await page.evaluate((roles) => {
    const rootStyles = getComputedStyle(document.documentElement);
    const probe = document.createElement("span");
    probe.setAttribute("aria-hidden", "true");
    probe.style.cssText =
      "position:fixed;left:-10000px;top:-10000px;width:1px;height:1px;visibility:hidden;pointer-events:none;";
    document.body.append(probe);

    const results: Partial<Record<DirectThemeRole, ProbeResult>> = {};
    try {
      for (const role of roles) {
        probe.style.color = `var(${role})`;
        probe.style.backgroundColor = `var(${role})`;
        const probeStyles = getComputedStyle(probe);
        results[role] = {
          declared: rootStyles.getPropertyValue(role).trim(),
          color: probeStyles.color,
          backgroundColor: probeStyles.backgroundColor,
        };
      }
    } finally {
      probe.remove();
    }

    return results as Record<DirectThemeRole, ProbeResult>;
  }, DIRECT_THEME_ROLES);

  const resolved = {} as ThemeRoles;
  for (const role of DIRECT_THEME_ROLES) {
    const result = probeResults[role];
    if (!result.declared) {
      throw new Error(`Browser did not resolve required theme role ${role}.`);
    }

    const color = parseCssColor(result.color, role);
    const backgroundColor = parseCssColor(result.backgroundColor, role);
    if (!sameColor(color, backgroundColor)) {
      throw new Error(
        `Browser resolved ${role} differently through color (${result.color}) and background-color (${result.backgroundColor}).`,
      );
    }
    resolved[role] = rgbToHex(color);
  }

  return resolved;
}

/** Calculate a WCAG 2.1 contrast ratio from browser-computed colors. */
export function contrastRatio(foreground: string, background: string): number {
  const foregroundLuminance = relativeLuminance(parseCssColor(foreground, "foreground"));
  const backgroundLuminance = relativeLuminance(parseCssColor(background, "background"));
  const lighter = Math.max(foregroundLuminance, backgroundLuminance);
  const darker = Math.min(foregroundLuminance, backgroundLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

function parseCssColor(value: string, role: string): RgbColor {
  const normalized = value.trim().toLowerCase();
  if (normalized.startsWith("#")) {
    return parseHexColor(normalized, role);
  }

  const rgbMatch = normalized.match(/^rgba?\((.*)\)$/);
  if (!rgbMatch) {
    throw new Error(`Expected an opaque RGB color for ${role}, received ${value}.`);
  }

  const components = rgbMatch[1].replace(/\s*\/\s*/, ",").split(/[\s,]+/).filter(Boolean);
  if (components.length !== 3 && components.length !== 4) {
    throw new Error(`Expected three RGB channels for ${role}, received ${value}.`);
  }

  const channels = components.slice(0, 3).map((component) => {
    const isPercent = component.endsWith("%");
    const numeric = Number.parseFloat(isPercent ? component.slice(0, -1) : component);
    const channel = isPercent ? (numeric * 255) / 100 : numeric;
    if (!Number.isFinite(channel) || channel < 0 || channel > 255) {
      throw new Error(`RGB channel for ${role} is outside 0-255: ${value}.`);
    }
    return Math.round(channel);
  });

  if (components.length === 4) {
    const alphaComponent = components[3];
    const isPercent = alphaComponent.endsWith("%");
    const alpha = Number.parseFloat(isPercent ? alphaComponent.slice(0, -1) : alphaComponent);
    const normalizedAlpha = isPercent ? alpha / 100 : alpha;
    if (!Number.isFinite(normalizedAlpha) || normalizedAlpha !== 1) {
      throw new Error(`Expected an opaque RGB color for ${role}, received ${value}.`);
    }
  }

  return [channels[0], channels[1], channels[2]];
}

function parseHexColor(value: string, role: string): RgbColor {
  const digits = value.slice(1);
  if (digits.length !== 3 && digits.length !== 6 || !/^[\da-f]+$/i.test(digits)) {
    throw new Error(`Expected a valid hex color for ${role}, received ${value}.`);
  }
  const expanded = digits.length === 3 ? digits.split("").map((digit) => digit + digit).join("") : digits;
  return [
    Number.parseInt(expanded.slice(0, 2), 16),
    Number.parseInt(expanded.slice(2, 4), 16),
    Number.parseInt(expanded.slice(4, 6), 16),
  ];
}

function relativeLuminance([red, green, blue]: RgbColor): number {
  const linearize = (channel: number): number => {
    const normalized = channel / 255;
    return normalized <= 0.03928
      ? normalized / 12.92
      : ((normalized + 0.055) / 1.055) ** 2.4;
  };

  return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue);
}

function rgbToHex([red, green, blue]: RgbColor): string {
  return `#${[red, green, blue]
    .map((channel) => channel.toString(16).padStart(2, "0"))
    .join("")}`;
}

function sameColor(first: RgbColor, second: RgbColor): boolean {
  return first.every((channel, index) => channel === second[index]);
}
