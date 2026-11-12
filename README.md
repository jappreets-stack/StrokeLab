<img src="docs/icon.png" width="128" alt="StrokeLab icon" align="right">

# StrokeLab

A private golf stats app for iPhone and Apple Watch, built in SwiftUI for one golfer and one home course.
The goal is simple: find out exactly where strokes go, with entry fast enough to use one-handed on the course.

## Features (Round 1 — iPhone)
- **Course preloaded** — Redwood Empire GCC, White tees (par 72, 68.7 / 124): yards, par and stroke index for all 18 holes.
- **Hole plan card** — tee club, target score, trouble side (OB / water / trees / bunker) and a note, shown at the top of every hole.
- **One-hand hole entry** — score, putts and tee shot up front, everything else (penalties, lost ball, tee club, putt details) behind one "More" button.
  Tee club is pre-filled from the plan; greens in regulation and up-and-downs are worked out automatically (with override).
- **Greens built in** — front / center / back of all 18 greens, computed from the course's OpenStreetMap outlines (green polygons + each hole's tee-to-green line), so GPS yardages work out of the box. You can still adjust any green by tapping the satellite map.
- **Hole map** — each hole opens on its satellite view (like SwingU) with big front / center / back yards on top, turned to face the green from where you stand. Tap any spot for yards to it and what's left to the green (a layup planner).
- **Putting** — first-putt length and how it finished (made / short / long / left / right) per hole, a green-reading note on each hole's plan card, and a phone-as-a-level tool for the practice green.
- **Swing coach** — records your swing at up to 240 fps (with a countdown so a propped-up phone works), tracks your body on every frame with Apple's Vision pose detection, finds address / top / impact / finish, and draws your hand path plus shaft and shoulder plane lines over the video. Measures tempo, early extension, posture loss, head movement, sway and turn, then gives on-device coaching cards with drills.
- **Warm-up tracking** — log whether you warmed up, with a built-in 5-minute routine, so the stats can show whether it matters.
- **Scores-only mode** for backfilling old rounds.
- **Private by design** — no accounts, no servers. All data lives in one JSON file on the phone, with export / restore for backups.

## How it works
- SwiftUI + Observation, MapKit (satellite imagery, tap-to-coordinate, camera heading from your position to the green), Core Location live updates.
- `Shared/` holds the course data and Codable models used by both the iPhone and Watch targets.
- Green in regulation = `score − putts ≤ par − 2`. Up & down = missed green and still made par or better.

### Swing analysis
- Two passes: a 30 fps scan finds the fastest hand speed (the downswing), then a detailed pass at up to 120 fps around it.
- Phases come from the hand path: top = highest hands before the fastest point, impact = lowest hands after it, takeaway = where the hands were last still.
- Distances are scaled from your torso length in the video (≈19"), so they're estimates; the camera angle (down-the-line vs face-on) is detected from how wide your shoulders look.

### Apple Watch
- Play a whole round without the phone: front / center / back yards from the watch's own GPS, the hole plan (club, target, trouble), and big glove-friendly buttons for score and putts.
- Holes change with arrow buttons only (no Digital Crown, so a glove can't flip holes by accident).
- Each round runs as a HealthKit Golf workout (heart rate, calories, distance), so the yardages stay on screen on every wrist raise and the round lands in Apple Fitness.
- Start a round on either device and the other picks it up (WatchConnectivity; starting on the iPhone opens the watch app and its workout). Scores tapped on the watch land in the phone's round.

## Roadmap
- Dashboard: average vs par by hole, worst holes, blow-ups, penalties & one-ball rounds, putting, front vs back, 10-round trend.
- Practice log: wedge carries by club and swing (easy / hard / all-out), 9-ball up-and-down drill.

## Credits
Course map data © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL).
