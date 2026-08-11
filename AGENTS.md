# Silencio The Dark Story - Roblox Horror Game

## Project Type
- **Platform:** Roblox Studio (Rojo project, NOT git repo)
- **Genre:** Co-op horror escape game
- **Setting:** Karnaval terbengkalai dengan puzzle & monster
- **Collaboration:** KARIS Studio × OnBlox Studio
- **Target Release:** End of September 2026

## Chapter 1: The Mask Maze
- **Puzzle Type:** Wheel of Fate trivia games
- **Key Assets:** Topeng + lukisan paintings
- **Tracker Sheet:** Google Sheet "TRACKER Silencio KARIS X OnBlox"
  - ID: `1GhFfDhEyBIKM9ypWBdlBXgLayqgViNT_W3vvAtHS_WA`
  - gid=1158016091
  - Total tasks: 33

## My Tasks (Erlangga/Aer)
### Task #10: NPC Monster Script (HIGH Priority, Deadline 2026-08-12)
- **Location:** `src/MonsterController.server.luau`
- **Architecture:** FSM (Finite State Machine) modular system
- **Components:**
  - `src/MonsterAI/Config` — Behavior parameters
  - `src/MonsterAI/StateMachine` — Core transition logic
  - `src/MonsterAI/SafeZoneManager` — Patrol boundaries
  - `src/MonsterAI/TargetFinder` — Player detection
  - `src/MonsterAI/NavigationManager` — Pathfinding
  - `src/MonsterAI/CombatManager` — Attack patterns
  - `src/MonsterAI/PatrolManager` — Idle exploration
  - `src/MonsterAI/AnimationManager` — Movement sequences

### Task #16: KEY SYSTEM (HIGH Priority, Deadline 2026-08-17)
- **Progression:** Control room key → Power switch → Carnival lights
- **Purpose:** Gating system for chapter completion

## Unity Teaching Projects (For Students)
- **Fayyadz:** Flappy Bird clone
- **Rezoz:** Coin Collect 3D lane runner
- **Teaching Approach:** MCP-assisted debugging, Inspector guidance
- **Best Practice:** Match request wording precisely when ambiguous
- **Roblox Analogy Interpretation:** Answer Unity-native questions
- **Animation Retargeting:** Verify Mixamo→Roblox works in both Blender and Studio

## Documentation
- **MoM PDF:** `Silencio MoM_0_.pdf` in project folder
- **Game Design:** Keep all rules documented in AGENTS.md
- **Never assume** — always ask for clarification on requirements

## Security Rules
- Never commit .env files or credentials to Git
- Rojo project structure must be maintained
- Tracker sheet access limited to team members only
