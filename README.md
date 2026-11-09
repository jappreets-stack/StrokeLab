# StrokeLab

A private golf stats app for iPhone (Apple Watch coming next), built in SwiftUI for one golfer and one home course.
The goal is simple: find out exactly where strokes go, with entry fast enough to use one-handed on the course.

## Features (Round 1 — iPhone)
- **Course preloaded** — Redwood Empire GCC, White tees (par 72, 68.7 / 124): yards, par and stroke index for all 18 holes.
- **Hole plan card** — tee club, target score, trouble side (OB / water / trees / bunker) and a note, shown at the top of every hole.
- **One-hand hole entry** — big glare-proof buttons for score, putts, tee shot result, tee club, penalties and lost ball.
  Tee club is pre-filled from the plan; greens in regulation and up-and-downs are worked out automatically (with override).
- **Green pins from satellite** — tap front / center / back of each green on Apple Maps imagery; live GPS yardages appear on each hole.
- **Hole map** — satellite view of each hole, turned to face the green from where you stand. Tap any spot for yards to it and what's left to the green (a layup planner).
- **Warm-up tracking** — log whether you warmed up, with a built-in 5-minute routine, so the stats can show whether it matters.
- **Scores-only mode** for backfilling old rounds.
- **Private by design** — no accounts, no servers. All data lives in one JSON file on the phone, with export / restore for backups.

## How it works
- SwiftUI + Observation, MapKit (satellite imagery, tap-to-coordinate, camera heading from your position to the green), Core Location live updates.
- `Shared/` holds the course data and Codable models used by both the iPhone and Watch targets.
- Green in regulation = `score − putts ≤ par − 2`. Up & down = missed green and still made par or better.

## Roadmap
- Apple Watch: front / center / back yardages, hole plan, score + putts with the Digital Crown, round as a golf workout.
- Dashboard: average vs par by hole, worst holes, blow-ups, penalties & one-ball rounds, putting, front vs back, 10-round trend.
- Practice log: wedge carries by club and swing (easy / hard / all-out), 9-ball up-and-down drill.
