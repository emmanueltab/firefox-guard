# Firefox Guard

A session-limited, AI-monitored browser launcher for Linux. Designed for households, institutions, or individuals who need structured and filtered internet access.

---

## Overview

Firefox Guard replaces the default Firefox launcher entirely. Every session must be explicitly requested, is time-limited, and is monitored in real time. If a search query is flagged, the session ends immediately and a cooldown is enforced before the browser can be reopened.

The system is built in layers. The first two layers are instant and require no internet — they check queries against local wordlists and URL patterns. The third layer uses a cloud AI model with live web search to evaluate queries that require contextual judgment.

---

## Session Flow

1. Cooldown is checked — if active, Firefox does not open
2. User sets a session length
3. Firefox launches and the session timer begins
4. Every search query is evaluated in real time
5. On session end or triggered close, a cooldown is enforced

---

## Filtering Layers

|       Layer       |                  Method                       | Speed    | API Cost          |
|-------------------|-----------------------------------------------|----------|-------------------|
| 0 — Wordlist      | Checks query against a custom word list       | Instant  | None              |
| 1 — URL Patterns  | Checks title against known danger patterns    | Instant  | None              |
| Whitelist         | Skips AI for known safe queries               | Instant  | None              |
| 2 — Groq AI       | Cloud AI evaluates query with live web search | 1-2 sec  | Free (rate limit) |

---

## Cooldown Tiers

| Trigger                      |  Cooldown  |
|------------------------------|------------|
| Session ends normally        | 5 minutes  |
| Manual close                 | 5 minutes  |
| Wordlist or pattern match    | 20 minutes |
| AI flags search              | 20 minutes |
| AI unavailable (rate limit)  | 5 minutes  |

---

## AI Layer

Firefox Guard uses **Groq compound-beta-mini** — a fast cloud AI model with built-in web search capability. Unlike simple keyword filters, it can look up unknown titles, names, and terms before making a judgment.

### What it catches that simpler filters miss
- Titles and names that appear innocent but lead to inappropriate content
- Misspelled or abbreviated versions of flagged terms
- Queries in foreign languages or alternative encodings
- Searches framed as innocent or educational but with inappropriate intent
- Individuals searched by name who are adult entertainers

### Prompt customization
The AI layer is only as effective as the prompt that guides it. The default `prompt.txt` is a starting point — **you will likely need to dedicate time to refining it based on your specific context and needs.** The prompt defines what counts as inappropriate, sets the tone of evaluation, and provides examples the model learns from. Treat it as an ongoing configuration, not a one-time setup.

### Graceful fallback
If Groq is unavailable or rate limited, the response returns null. Firefox Guard treats this as a fail-safe — the session closes with a 5 minute cooldown rather than allowing unfiltered queries through.

---

## Browser Hardening

Firefox Guard is designed to work alongside the following browser-level protections:

- **Private browsing disabled** via Firefox policies
- **Extensions locked** — force-installed extensions cannot be removed by the user
- **No new extensions** can be installed by the user
- **Google SafeSearch forced** via hosts file redirect
- **High-risk platforms blocked** via hosts file

---

## Files

| File                  |                  Purpose                             |
|-----------------------|------------------------------------------------------|
| `firefox-guard.sh`    | Main script — replaces the Firefox launcher          |
| `wordlist.txt`        | Words that trigger instant session close (customize) |
| `patterns.txt`        | URL patterns that trigger instant session close      |
| `prompt.txt`          | AI evaluation prompt — requires ongoing tuning       |
| `groq_api_key.txt`    | Groq API key (not included, add your own)            |
| `install.sh`          | Automated setup script (in progress)                 |

---

## Requirements

- Linux (Debian/Ubuntu based)
- Firefox
- Groq API key (free at console.groq.com)
- xdotool
- zenity
- jq
- curl

---

## Installation (manual)

```bash
# Copy script
sudo cp firefox-guard.sh /usr/local/bin/firefox-guard
sudo chmod +x /usr/local/bin/firefox-guard

# Symlink Firefox to firefox-guard
sudo ln -sf /usr/local/bin/firefox-guard /usr/bin/firefox

# Create config directory
mkdir -p ~/.config/firefox-guard

# Add your Groq API key
echo "your_api_key_here" > ~/.config/firefox-guard/groq_api_key.txt

# Copy config files
cp wordlist.txt ~/.config/firefox-guard/wordlist.txt
cp patterns.txt ~/.config/firefox-guard/patterns.txt
cp prompt.txt ~/.config/firefox-guard/prompt.txt
```

---

## Key Commands

```bash
# Start a session
firefox-guard <minutes>

# Reset cooldown (admin only)
rm ~/.firefox_cooldown ~/.firefox_cooldown_duration

# View activity log
cat ~/.config/firefox-guard/activity.log

# View flagged entries only
grep "FLAGGED\|AI flagged\|AI UNAVAILABLE" ~/.config/firefox-guard/activity.log
```

---

## Additional Tips

Firefox Guard is one component of a broader discipline system. The following measures complement it and are worth implementing alongside it.

### 1. Replace browser use with local tools
The less time spent in a browser, the less exposure to risk. Many common tasks that drive browser use can be handled locally:
- **Email** — install a local client such as Thunderbird or neomutt instead of using webmail
- **AI assistants** — Claude Desktop, for example, can be installed as a native application
- **Music** — use a local player such as cmus with downloads managed via yt-dlp
- **Code and version control** — use the GitHub CLI (`gh`) instead of the GitHub website
- **Calendar and tasks** — use calcurse or similar CLI tools

The goal is to make the browser a tool of last resort rather than the default environment.

### 2. Set up DNS-level filtering
DNS filtering blocks entire categories of websites before they ever load, at the network level. This works across all browsers and applications on the machine.

- Set your router's DNS to a filtering service such as **OpenDNS** or **Cloudflare for Families** (`1.1.1.3`)
- Also configure DNS on the machine itself via `systemd-resolved` so the filter applies even outside the home network
- This provides a baseline layer of protection independent of Firefox Guard

### 3. Use uBlock Origin and Unhook in Firefox
Even within a session, browser extensions add an additional layer of control:
- **uBlock Origin** can block all images sitewide, preventing visual content from loading regardless of what page is visited
- **Unhook** removes YouTube recommendations, trending, and suggested content, limiting YouTube to intentional search use only

Both extensions can be force-installed and locked via Firefox policies so the user cannot remove or disable them. See the Browser Hardening section above.

### 4. Maintain a hosts file blocklist and force Google SafeSearch
The `/etc/hosts` file can be used to block specific domains at the OS level — faster and more reliable than DNS for known bad actors:
- Maintain a blocklist of high-risk domains (image boards, adult platforms, fan art communities, etc.)
- Force Google SafeSearch by redirecting `google.com` to Google's SafeSearch IP (`216.239.38.120`) in the hosts file — this enforces safe mode on all searches and cannot be bypassed by the user in the browser

### 5. Remove risky applications from Android via ADB
Smartphones are often the weakest point in any discipline system. Android allows removal of system and pre-installed apps without rooting using ADB:

```bash
# Connect device with USB debugging enabled
adb shell pm uninstall -k --user 0 com.google.android.youtube
adb shell pm uninstall -k --user 0 com.google.android.apps.youtube.music
# Add any other package names to remove
```

This removes apps for the current user without permanently deleting them from the system. They can be restored if needed:

```bash
adb shell cmd package install-existing com.google.android.youtube
```

### 6. become Catholic

Addiction to media and pornography is only a glimpse of what we become when we abandon Christ and the laws of His Church. Without a firm pillar of faith and hope, we will become the worst versions of ourselves.

"And since they did not see fit to acknowledge God, God gave them up to a debased mind to do what ought not to be done." (Romans 1:28)

---

## Philosophy

Unrestricted browser access is not a neutral default. Firefox Guard is built on the premise that intentional, time-limited, and monitored access is healthier than passive, unlimited browsing. The goal is not surveillance but structure.
