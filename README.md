# Productjvity

A financially backed accountability platform that turns goals and commitments into measurable outcomes.

**Commit → Act → Verify → Complete → Reward**

If a commitment is not completed:

**Commit → Fail → Forfeit → Allocate**

## Overview

Productjvity helps individuals and organisations follow through on meaningful goals by adding structure, measurement, and real consequences to commitment.

Users commit to a specific goal, agree to defined success criteria and, where applicable, place money at stake. The platform provides reminders, progress tracking, and verification. Successful users receive their committed funds and/or a reward. Users who fail may forfeit a predetermined portion, which can fund rewards for successful users, with a disclosed portion retained as platform breakage revenue.

The platform can also be used as **accountability infrastructure** by institutions that want to run their own accountability programmes without building the underlying system.

Core principle: goals become commitments, commitments become measurable, measurement creates accountability, accountability drives completion, completion creates rewards.

## Objectives

- Help people follow through on meaningful goals
- Create stronger accountability through financial commitment
- Make goals specific, measurable, and time-bound
- Provide continuous visibility of progress
- Reward successful completion
- Enable institutions to run accountability programmes at scale
- Provide a trusted, transparent system for commitment, verification, reward, and forfeiture

## Who It's For

### Individual Users
Personal, professional, financial, educational, health, lifestyle, or other measurable goals. Examples:
- Completing a course or certification
- Saving toward a defined objective
- Completing a training programme
- Building a habit
- Structured 30-day challenges

### Institutional Users
Organisations running accountability programmes for members, employees, students, or communities:
- Churches and religious organisations
- Schools and universities
- Training providers
- Employers
- Professional organisations
- Communities and membership groups
- Coaching organisations

### Platform Administrator
Operates the overall service, institutional relationships, programme structures, financial rules, and verification arrangements.

## How It Works

### 1. Discover
Browse available programmes or create a personal commitment. Before committing, see:
- Goal and requirements
- Duration
- Stake amount, if any
- Success / failure criteria
- Reward
- Forfeiture amount and allocation

All material terms are presented upfront.

### 2. Create or Join a Commitment
Agree to:
- Objective
- Timeframe
- Milestones / requirements
- Verification method
- Financial commitment
- Reward structure
- Consequence for non-completion

### 3. Active Commitment
During the commitment period:
- View goal, deadline, and progress
- See completed vs outstanding requirements
- Receive reminders and accountability prompts
- Submit evidence where required

### 4. Verification
Performance is assessed against the predefined success criteria. Rules are not changed retrospectively to disadvantage the user.

### 5. Completion
If successful:
- Commitment marked successful
- Return of applicable funds + reward
- Recorded in user history

If unsuccessful:
- Commitment marked unsuccessful
- Forfeiture calculated per agreed rules
- Forfeited amount allocated per programme rules
- Outcome visible to user

## Institutional Programmes

Institutions can:

**Create a programme** — name, objective, participants, dates, eligibility, commitment requirements, success criteria, verification, rewards, forfeiture, and allocation rules.

**Enrol participants** — individually or in groups, with rules accepted before joining.

**Manage the programme** — monitor enrolment / participation / progress, send reminders, review evidence, verify completion, manage exceptions.

**Review results** — participants, completion rate, amounts committed / returned, rewards, forfeitures, and fees.

## Rewards and Breakage Model

When a user fails, a predetermined portion may be forfeited into a Breakage Pool, allocated between:

1. Successful users — as additional rewards
2. Platform — as disclosed breakage fee
3. Institution / sponsor — where programme rules permit

Allocation is defined and disclosed **before** users commit.

Example:
- User commits ₦100,000 with 50% max forfeiture
- On failure, up to ₦50,000 is subject to forfeiture
- Split between successful-user reward pool and platform revenue per programme rules

The commercial model prioritises successful completion, not failure.

## Business Model

- Breakage fees (disclosed portion of forfeitures)
- Transaction fees (deposits, withdrawals, rewards, settlements)
- Institutional / subscription fees
- Programme fees
- API / infrastructure fees
- Enterprise fees
- Verification fees

## Key Product Requirements

- **Personal commitments:** define goal, deadline, success criteria, stake, track progress, submit evidence, complete
- **Group accountability:** shared challenges with appropriate privacy
- **Notifications:** confirmations, deadlines, missed milestones, reminders, verification, completion, rewards, forfeitures
- **User dashboard:** active / completed commitments, deadlines, amounts at risk, rewards earned, history, available programmes
- **Institutional dashboard:** programme and participant overview
- **Transparency:** no hidden material financial conditions
- **Disputes:** process for incorrect verification, technical failure, disputed status, settlement errors, exceptional circumstances
- **History / reputation:** accountability profile of completions, subject to consent
- **Administration:** manage institutions, programmes, rules, financial activity, disputes, reporting, audit trail

## Product Principles

- Clarity — understand exactly what you're committing to
- Measurability — objective success criteria
- Accountability — meaningful incentives
- Fairness — no undisclosed or retrospective conditions
- Transparency — visible financial consequences
- Positive incentives — encourage completion
- Trust — rules administered as agreed
- Flexibility — support varied programme types

## Documentation

Full specification: [`docs/PRODUCTJVITY PRODUCT REQUIREMENTS DOCUMENT.md`](docs/PRODUCTJVITY%20PRODUCT%20REQUIREMENTS%20DOCUMENT.md)

## Project Status

Working prototype in progress. The current local build supports commitments,
milestones, evidence uploads, verification, simulated settlement, institutions,
notifications, disputes, and an audit trail. It is not yet production-ready:
real authentication, PostgreSQL persistence, private production evidence
storage, payments, and deployment hardening are the next milestones.

Development documentation lives in [`design/`](design/) and [`docs/`](docs/).

## Vision

Build global accountability infrastructure where individuals and organisations put meaningful commitments behind their goals — directly or via third-party institutions and applications.
