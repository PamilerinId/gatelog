import type { Role } from "./types";

// Who sees what. Each role gets its own first screen (/dashboard) and at most four menu items.
// Pages check `canOpen` so a role never lands on a screen meant for someone else, and actions are
// only shown where the API allows them (the API is still the one that decides).

export type NavItem = { href: string; label: string };

export type Persona = "office" | "security" | "exco" | "treasurer";

export function persona(role: Role): Persona {
  if (role === "admin") return "office";
  if (role === "security_head") return "security";
  if (role === "treasurer") return "treasurer";
  return "exco"; // committee and association users
}

export function nav(role: Role): NavItem[] {
  switch (persona(role)) {
    case "office":
      return [
        { href: "/dashboard", label: "Today" },
        { href: "/dashboard/register", label: "Homes" },
        { href: "/dashboard/gate", label: "Gates & guards" },
        { href: "/dashboard/settings", label: "Settings" },
      ];
    case "security":
      return [
        { href: "/dashboard", label: "Live" },
        { href: "/dashboard/gate-log", label: "Gate log" },
        { href: "/dashboard/shifts", label: "Shifts" },
        { href: "/dashboard/guards", label: "Guards" },
      ];
    case "treasurer":
      return [
        { href: "/dashboard", label: "Messages" },
        { href: "/dashboard/reports", label: "Monthly report" },
      ];
    default:
      return [
        { href: "/dashboard", label: "Today" },
        { href: "/dashboard/gate-log", label: "Gate log" },
        { href: "/dashboard/reports", label: "Monthly report" },
      ];
  }
}

/** Pages beyond the menu, and who may open them. The menu pages are listed too. */
const PAGES: Record<string, readonly Persona[]> = {
  register: ["office"],
  gate: ["office"],
  settings: ["office"],
  import: ["office"],
  "emergency-numbers": ["office", "security", "exco"],
  "gate-log": ["office", "security", "exco"],
  shifts: ["office", "security"],
  guards: ["security"],
  reports: ["office", "exco", "treasurer"],
  messaging: ["office", "exco", "treasurer"],
  shuttle: ["office", "security", "exco"],
};

export function canOpen(role: Role, page: keyof typeof PAGES) {
  return PAGES[page].includes(persona(role));
}

/** Only the estate admin changes anything. */
export const isAdmin = (role: Role) => role === "admin";

/** Voice clips, gate photos, shift selfies, typing a name in: the admin and the security head. */
export const seesMedia = (role: Role) => role === "admin" || role === "security_head";

/** Where the riders are: the admin, the committee and the security head (not the treasurer). */
export const seesPositions = (role: Role) => role === "admin" || role === "committee" || role === "security_head" || role === "ops";
