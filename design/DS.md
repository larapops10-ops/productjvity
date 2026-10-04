# Productjvity design system

## Principles

The interface should feel calm, serious, and encouraging. It must explain consequences plainly; it must never make forfeiture feel like a surprise or a game.

## Tokens

| Token | Value | Use |
| --- | --- | --- |
| `ink` | `#1C1917` | Primary text |
| `surface` | `#FFFFFF` | Cards and forms |
| `background` | `#FAF8F5` | Page background |
| `accent` | `#5F4BE0` | Primary action and progress |
| `accent-soft` | `#EFEDFD` | Selected state |
| `warning` | `#B45309` | At-risk deadline |
| `danger` | `#B91C1C` | Failure and forfeiture |
| `success` | `#15803D` | Verified completion |

Use an 8px spacing scale, 12px form corners, and at least 44px touch targets. Body copy must meet WCAG AA contrast.

## Shared components

- `TermsPanel`: objective, measurement, start/end dates, proof method, success and failure definitions, stake, maximum loss, reward, split, fees, exception and dispute process. It is shown before acceptance and on the final receipt.
- `ProgressBar`: progress with text alternative such as “2 of 4 milestones complete”.
- `DeadlineCountdown`: a date plus clear urgency text, never colour alone.
- `EvidenceUploader`: allowed file formats, size limit, optional note, upload progress, and a clear privacy statement.
- `OutcomeReceipt`: returned amount, forfeited amount, reward, fees, allocation, and rules-version hash.
- `Leaderboard`: opt-in public names; aggregate counts by default.

## Accessibility requirements

- Every input has a visible label and useful error text.
- Keyboard focus is visible; actions work without a pointer.
- Status changes are announced to screen readers.
- Financial values include currency and are not represented by colour alone.
