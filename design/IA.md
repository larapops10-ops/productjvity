# Productjvity information architecture

## Public

| Route | Purpose | Primary action |
| --- | --- | --- |
| `/` | Explain accountable commitments and trust principles. | Create a commitment |
| `/discover` | Browse open institutional programmes. | View programme |
| `/programmes/:id` | Explain a programme and all pinned terms. | Join programme |

## Member

| Route | Purpose | Primary action |
| --- | --- | --- |
| `/dashboard` | Show active work, deadlines, money at risk, and history. | Open commitment |
| `/commitments/new` | Four-step commitment wizard. | Accept terms and create |
| `/commitments/:id` | Track milestones, submit proof, and see a receipt. | Submit for verification |
| `/notifications` | Review reminders and delivery preferences. | Update preferences |
| `/users/:id/history` | Show consent-controlled completion history. | Change visibility |

## Institution and platform

| Route | Purpose | Primary action |
| --- | --- | --- |
| `/institutions/:id` | View an institution and its programmes. | Create programme |
| `/institutions/:id/programmes/new` | Define a programme and its version-one rules. | Publish programme |
| `/programmes/:id/manage` | Review enrolment, proof, exceptions, and results. | Decide verification |
| `/admin` | Review institutions, financial activity, disputes, and audit logs. | Resolve dispute |

## Navigation rules

- A person always sees their own dashboard first after sign-in.
- Money, rules, and proof are never hidden behind a secondary screen before joining.
- An institution reviewer can only see programmes for their own institution.
- Admin controls are never shown to ordinary members.
