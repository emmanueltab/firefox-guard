# Firefox Guard 🚪

A browser bouncer. It checks you before you get in, watches you while you're inside, and throws you out if you misbehave.

## How it works

Firefox Guard acts as a single unified gatekeeper between you and your browser.

### Before you get in
- Checks if you are in a cooldown period (5 min normal, 20 min flagged)
- Blocks multiple instances
- Asks you to set a session length

### While you are inside
- Blocks all images by default via uBlock Origin
- Monitors your search queries in real time
- Runs every query through 3 layers of filtering

### If you misbehave
- Firefox is killed immediately
- A cooldown is enforced before you can re-enter
- Cooldown length depends on what triggered the close

---

## Filtering Layers

|       Layer      |                  Method                   | Speed   |    API Cost    |
|------------------|-------------------------------------------|---------|----------------|
| 0 — Wordlist     | Checks query against a custom word list   | Instant | None           |
| 1 — URL Patterns | Checks URL against known danger patterns  | Instant | None           |
| 2 — Ollama AI    | Local AI evaluates query using web search | 1-2 sec | Free (100/day) |

---

## Cooldown Tiers

| Trigger                      |  Cooldown  |
|------------------------------|------------|
| Session ends normally        | 5 minutes  |
| Manual close                 | 5 minutes  |
| Wordlist or pattern match    | 20 minutes |
| AI flags search              | 20 minutes |

---

## Files

| File               |                  Purpose                        |
|--------------------|-------------------------------------------------|
| `firefox-guard.sh` | Main script — replaces firefox-limited entirely |
| `wordlist.txt`     | Custom words that trigger instant kill          |
| `patterns.txt`     | URL patterns that trigger instant kill          |
| `prompt.txt`       | Editable AI evaluation prompt                   | 
| `install.sh`       | Automated setup script                          |

---

## Requirements

- Linux (Debian/Ubuntu based)
- Firefox
- Ollama
- uBlock Origin (Firefox extension)
- xdotool
- zenity

---

## Philosophy

Every layer removes a reason to keep the browser open. The goal is not punishment but protection.
