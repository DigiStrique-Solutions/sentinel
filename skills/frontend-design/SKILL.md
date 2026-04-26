---
name: sentinel-frontend-design
description: Use when generating frontend code (React/Vue/Svelte components, pages, or full UIs) where visual quality matters. Produces distinctive, production-grade interfaces that avoid the generic "AI-built" look. Activates when the user asks for a component, a page, a landing page, a dashboard, an admin panel, or any UI that's user-facing rather than internal tooling.
origin: sentinel
---

# Frontend Design

Generate frontend code that doesn't look like every other AI-generated UI. The default failure mode of LLM frontend output is *generic* — same shadcn card, same gradient, same purple-to-pink hero, same Lucide icon, same animate-pulse skeleton. Production-quality frontend has specificity. This skill is about getting there.

## What "generic AI aesthetic" looks like (and why it's a problem)

Telltale signs:
- Gray text on white card with `rounded-lg shadow-md`
- A purple-to-pink gradient hero
- A Lucide icon next to every label, regardless of whether it adds info
- Three-column feature grid with identical-looking icons
- `animate-pulse` skeletons that look the same in every app
- Buttons that say `Get Started →` with the arrow doing all the visual work

The problem isn't that any one of these is wrong. The problem is the *combination* — it's recognizable as machine output the moment you see it. Real product UIs make decisions; generic UIs hedge.

## The protocol

### Step 1: Anchor on a real reference

Before writing any code, ask the user (or pick yourself, if the user is open):

- A specific product whose UI feels like the right tone (Linear, Vercel, Stripe, Notion, Figma, Arc, Raycast, Cursor, Mercury, Pitch, etc.)
- A specific industry/audience (developer tools, fintech, design tools, B2B ops, consumer entertainment)
- A specific emotional register (clinical, playful, brutal, soft, futuristic)

**One specific reference beats three generic adjectives.** "Like Linear" is a sharper instruction than "modern, clean, professional."

### Step 2: Make the unique decisions before the common ones

The common decisions (button radius, card shadow, base font) get made by every UI. The unique decisions are what give it identity. Make those first:

- **One signature element** — what's the *one* thing this UI does visually that another UI wouldn't?
  Examples: aggressive type scale, asymmetric layout, animated hover state, custom illustration, unconventional color palette, bold use of negative space, oversized first letter, hand-drawn dividers
- **Color decision with intent** — not "primary blue" — *which* blue, why that one, where it's used vs withheld
- **Type decision with intent** — not "Inter" — what scale, what contrast between sizes, what role for italic/weight
- **Density decision** — is this UI breathing (lots of whitespace) or dense (information-rich)?

If you can't articulate any of these in one sentence each, you'll produce a generic UI.

### Step 3: Steal specifically, not generally

You are allowed and encouraged to take specific decisions from real UIs. "Linear's command palette uses a 0.05s ease-out for its open animation and the items have a 6px left padding when focused" is fine — that's a specific borrowed decision. "Make it feel like a modern SaaS app" is not — it's the path back to generic.

When you reference, be specific about *what* you're taking:
- The information density (e.g., Linear)
- The motion vocabulary (e.g., Vercel)
- The empty-state treatment (e.g., Notion)
- The focus state (e.g., Raycast)
- The error treatment (e.g., Stripe)

You can mix sources — Linear's density + Stripe's color discipline + Notion's empty states is its own thing.

### Step 4: Use the design system if one exists

Before generating new visual decisions, check the project for:
- A design tokens file (`tokens.json`, `theme.ts`, Tailwind config with custom values)
- An existing component library (`src/components/ui/`)
- A documented design language (`docs/design/`, Storybook stories)

If any exist, *use them*. Generating fresh visual decisions when the project already has a system is how UIs become inconsistent. Match the existing system; don't add a third opinion.

### Step 5: Production-quality details that distinguish

Things that move work from "looks fine" to "looks shipped":

- **States, not just default** — hover, focus, active, disabled, loading, error, empty. Most generic AI output ships only the default state.
- **Real content, not lorem** — Use plausible product copy, not "Lorem ipsum" or "Card title." If you don't know the actual copy, use placeholders that *signal* what real copy would look like in shape and length.
- **Visual hierarchy proof** — squint at the result. Does the most important element pop? If everything is the same weight, the hierarchy is broken.
- **Accessibility as a first-class decision** — focus rings visible, color contrast meets WCAG AA at minimum, keyboard navigation works, semantic HTML
- **Motion with purpose** — no animation that doesn't serve a function. `animate-bounce` on a logo for no reason is the generic-AI tell.
- **Responsive thinking up front** — at least state how it changes at sm/md/lg breakpoints, even if you only output one breakpoint's code

### Step 6: Ship with a styled README of decisions

When you finish a non-trivial UI, write a short note explaining the decisions made:

```markdown
## Design notes

Reference: <specific source>
Signature element: <one thing>
Color: <brief>
Type: <brief>
Density: <breathing | balanced | dense>

Specific borrowings:
- Density treatment from Linear
- Empty state pattern from Notion
- Focus rings from Raycast
```

This makes future changes consistent — anyone editing the component knows what decisions to preserve.

## Anti-patterns to actively avoid

- **The default shadcn card** — `bg-card text-card-foreground rounded-lg shadow-sm border` with no further decisions. Fine as a starting point, never as a finished product.
- **Gradient as decoration** — every hero gets a purple-pink gradient. Use gradients only when they signal something (e.g., representing a transition, mapping a value).
- **Lucide icon next to every label** — icons should add information, not decoration. If the label is "Settings", a gear icon adds nothing.
- **Three-column feature grid** — if your homepage has a "Features" section that's three identical columns of icon + heading + description, that's the generic. Make it less symmetric or skip the section entirely.
- **Skeletons that don't match the real layout** — `animate-pulse` rectangles that don't approximate the actual content shape are worse than no skeleton.
- **Buttons styled identically regardless of importance** — primary/secondary/tertiary should look meaningfully different, not just slightly different shades.

## Integration

- **Use after:** sentinel-brainstorm (when the spec mentions visual/UX requirements)
- **Use during:** sentinel-writing-plans (each visual component task references this skill in its spec)
- **Use during:** sentinel-subagent-driven-development (frontend-task subagent loads this skill in addition to the general implementer prompt)
- **Pairs with:** the project's design tokens / component library if present (priority over fresh decisions)
