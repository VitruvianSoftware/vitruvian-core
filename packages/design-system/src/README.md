# Src

## Overview
Component package providing implementation for `packages/design-system/src`.

## Interface
- `[Button.stories.tsx:Primary]`
- `[Button.stories.tsx:Secondary]`
- `[Button.stories.tsx:Ghost]`
- `[Button.stories.tsx:Danger]`
- `[Button.stories.tsx:AllVariants]`
- `[Button.stories.tsx:Sizes]`
- `[Button.stories.tsx:Block]`
- `[Button.tsx:ButtonVariant]`
- `[Button.tsx:ButtonProps]`
- `[Button.tsx:Button]`
- `[Card.stories.tsx:Default]`
- `[Card.stories.tsx:Grid]`
- `[Card.stories.tsx:Surfaces]`
- `[Card.stories.tsx:WithTags]`
- `[Card.tsx:CardProps]`
- `[Card.tsx:Card]`
- `[DataDisplay.stories.tsx:Signals]`
- `[DataDisplay.stories.tsx:Readouts]`
- `[DataDisplay.stories.tsx:Capacity]`
- `[DataDisplay.stories.tsx:Sparklines]`

## Invariants
- [Form.stories.tsx:86]: `<Switch label="Require approval" defaultChecked />`

## Side Effects
- [Overlay.stories.tsx:155]: `const [query, setQuery] = React.useState("");`
- [Overlay.stories.tsx:166]: `query={query}`
- [Overlay.tsx:349]: `query: string;`
- [Overlay.tsx:362]: `query,`
- [Overlay.tsx:392]: `value={query}`
- [Patterns.stories.tsx:340]: `<code className="text-xs">http://localhost:8080/callback</code>`
- [Patterns.stories.tsx:420]: `Exec Transcript`

## Verification
- Run: `bazel test //packages/design-system/src/...`
