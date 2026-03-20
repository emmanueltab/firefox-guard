#!/bin/bash

# ============================================================
# FIREFOX GUARD
# A browser bouncer — session limiter + AI content filter
# ============================================================

MINUTES=$1
COOLDOWN_FILE="/home/$USER/.firefox_cooldown"
COOLDOWN_DURATION_FILE="/home/$USER/.firefox_cooldown_duration"
GUARD_KILL_FILE="/home/$USER/.firefox_guard_kill"
WORDLIST="$HOME/.config/firefox-guard/wordlist.txt"
PATTERNS="$HOME/.config/firefox-guard/patterns.txt"
PROMPT_FILE="$HOME/.config/firefox-guard/prompt.txt"
LOG_FILE="$HOME/.config/firefox-guard/activity.log"

# Redirect stderr to stdout by default
exec 2>&1
# ============================================================
# PREVENT MULTIPLE INSTANCES
# ============================================================
LOCK_FILE="/tmp/firefox-guard.lock"

if [ -f "$LOCK_FILE" ]; then
    zenity --error --text="Firefox is already running." --title="Firefox Guard"
    exit 1
fi

touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# ============================================================
# CHECK COOLDOWN
# ============================================================
if [ -f "$COOLDOWN_FILE" ]; then
    LAST=$(cat "$COOLDOWN_FILE")
    DURATION=$(cat "$COOLDOWN_DURATION_FILE" 2>/dev/null || echo 300)
    NOW=$(date +%s)
    ELAPSED=$(( NOW - LAST ))
    REMAINING=$(( DURATION - ELAPSED ))
    if [ "$REMAINING" -gt 0 ]; then
        if [ "$DURATION" -eq 1200 ]; then
            zenity --error --text="A flagged search triggered a 20 minute cooldown. $REMAINING seconds remaining." --title="Firefox Guard"
        else
            zenity --error --text="Cooldown active. Please wait $REMAINING more seconds before opening Firefox." --title="Firefox Guard"
        fi
        exit 1
    fi
fi

# ============================================================
# SESSION LENGTH
# ============================================================
if [ -z "$MINUTES" ]; then
    MINUTES=$(zenity --entry \
        --title="Firefox Guard" \
        --text="How many minutes do you want to use Firefox?" \
        --entry-text="10")
    if [ $? -ne 0 ] || [ -z "$MINUTES" ]; then
        exit 0
    fi
fi

if ! [[ "$MINUTES" =~ ^[0-9]+$ ]] || [ "$MINUTES" -le 0 ]; then
    zenity --error --text="Please enter a valid number of minutes." --title="Firefox Guard"
    exit 1
fi

SECONDS_LIMIT=$((MINUTES * 60))

zenity --question \
    --title="Firefox Guard" \
    --text="Open Firefox for $MINUTES minute(s)?" \
    --ok-label="Yes" --cancel-label="Cancel"
if [ $? -ne 0 ]; then
    exit 0
fi

# ============================================================
# LAUNCH FIREFOX
# ============================================================
export MOZ_APP_LAUNCHER=/usr/bin/firefox
/usr/lib/firefox/firefox "${@:2}" 2>/dev/null &
FF_PID=$!

echo "$(date) | SESSION STARTED | $MINUTES minutes" | tee -a "$LOG_FILE"

# ============================================================
# SESSION TIMER
# ============================================================
(
    sleep $SECONDS_LIMIT
    if kill -0 $FF_PID 2>/dev/null; then
        zenity --warning --text="Your $MINUTES minute Firefox session has ended. 5 minute cooldown started." --title="Session Over" &
        kill $FF_PID
        echo "$(date +%s)" > "$COOLDOWN_FILE"
        echo 300 > "$COOLDOWN_DURATION_FILE"
    fi
) &

# 1 minute warning
if [ "$MINUTES" -gt 2 ]; then
    (
        sleep $(( SECONDS_LIMIT - 60 ))
        if kill -0 $FF_PID 2>/dev/null; then
            zenity --warning --text="1 minute remaining in your Firefox session." --title="Firefox Guard" &
        fi
    ) &
fi

# ============================================================
# GUARD — URL MONITOR + AI FILTER
# ============================================================
(
    sleep 3
    LAST_QUERY=""
    while kill -0 $FF_PID 2>/dev/null; do
        sleep 1

        # Only scan if Firefox is the active window
        ACTIVE_PID=$(xdotool getactivewindow getwindowpid 2>/dev/null)
        if [ "$ACTIVE_PID" != "$FF_PID" ]; then
            continue
        fi

        # Read current Firefox window title
        TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null)

        # Extract search query from title
        QUERY=$(echo "$TITLE" | sed 's/ - Google Search.*//' | sed 's/ — Mozilla Firefox.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')


        if [ -z "$QUERY" ] || [ "$QUERY" = "$LAST_QUERY" ]; then
            continue
        fi

        # Skip generic Firefox titles
        case "$QUERY" in
            "Mozilla Firefox"|"Restore Session"|"New Tab")
                continue
                ;;
        esac

        LAST_QUERY="$QUERY"

        # Log query
        echo "$(date) | TITLE: $TITLE | QUERY: $QUERY" | tee -a "$LOG_FILE"

        # Layer 0 — Wordlist check
        if [ -f "$WORDLIST" ]; then
            while IFS= read -r word; do
                if [ -z "$word" ]; then continue; fi
                if echo "$QUERY" | grep -qi "$word"; then
                    echo "$(date) | FLAGGED WORD: $word | QUERY: $QUERY" | tee -a "$LOG_FILE"
                    zenity --error --text="Flagged word detected: '$word'. 20 minute cooldown activated." --title="Firefox Guard" &
                    kill $FF_PID
                    echo "$(date +%s)" > "$COOLDOWN_FILE"
                    echo 1200 > "$COOLDOWN_DURATION_FILE"
                    touch "$GUARD_KILL_FILE"
                    exit 0
                fi
            done < "$WORDLIST"
        fi

        # Layer 1 — URL pattern check
        if [ -f "$PATTERNS" ]; then
            while IFS= read -r pattern; do
                if [ -z "$pattern" ]; then continue; fi
                if echo "$TITLE" | grep -qi "$pattern"; then
                    echo "$(date) | FLAGGED PATTERN: $pattern | TITLE: $TITLE" | tee -a "$LOG_FILE"
                    zenity --error --text="Flagged URL pattern detected: '$pattern'. 20 minute cooldown activated." --title="Firefox Guard" &
                    kill $FF_PID
                    echo "$(date +%s)" > "$COOLDOWN_FILE"
                    echo 1200 > "$COOLDOWN_DURATION_FILE"
                    touch "$GUARD_KILL_FILE"
                    exit 0
                fi
            done < "$PATTERNS"
        fi

        # Whitelist — skip AI check for known safe queries
        case "${QUERY,,}" in
            "google maps"|"google drive"|"google docs"|"google sheets"|"gmail"|"youtube" \
            |"wikipedia"|"weather"|"houston weather"|"ust"|"cat photos"|"cat"|"cats" \
            |"dogs"|"dog"|"math"|"homework"|"calculator" \
            |"bible"|"rosary"|"catholic"|"news"|"sports"|"nasa"|"khan academy" \
            |"duolingo"|"spotify"|"netflix"|"amazon"|"ebay"|"walmart")
                echo "$(date) | WHITELISTED: $QUERY" | tee -a "$LOG_FILE"
                continue
                ;;
        esac

        # Layer 2 — Groq AI check
        GROQ_KEY=$(cat "$HOME/.config/firefox-guard/groq_api_key.txt" 2>/dev/null)
        if [ -n "$GROQ_KEY" ]; then
            PROMPT=$(cat "$PROMPT_FILE" 2>/dev/null)
            RESPONSE=$(curl -s -X POST https://api.groq.com/openai/v1/chat/completions \
                -H "Authorization: Bearer $GROQ_KEY" \
                -H "Content-Type: application/json" \
                -d "{
                    \"model\": \"compound-beta-mini\",
                    \"messages\": [
                        {\"role\": \"system\", \"content\": $(echo "$PROMPT" | jq -Rs .)},
                        {\"role\": \"user\", \"content\": $(echo "Evaluate this search query: $QUERY" | jq -Rs .)}
                    ]
                }" | jq -r '.choices[0].message.content' 2>/dev/null)
            # Abort if Firefox already closed
            if ! kill -0 $FF_PID 2>/dev/null; then
                exit 0
            fi
            echo "$(date) | AI RESPONSE: $RESPONSE" | tee -a "$LOG_FILE"

            if echo "$RESPONSE" | grep -qi "^\s*YES"; then
                echo "$(date) | AI FLAGGED: $QUERY" | tee -a "$LOG_FILE"
                zenity --error --text="AI flagged your search: '$QUERY'. 20 minute cooldown activated." --title="Firefox Guard" &
                kill $FF_PID
                echo "$(date +%s)" > "$COOLDOWN_FILE"
                echo 1200 > "$COOLDOWN_DURATION_FILE"
                touch "$GUARD_KILL_FILE"
                exit 0
            fi
        else
            echo "$(date) | Groq API key not found — skipping AI check" | tee -a "$LOG_FILE"
        fi

    done
) &

# ============================================================
# WAIT FOR FIREFOX TO CLOSE
# ============================================================
wait $FF_PID

echo "$(date) | SESSION ENDED" | tee -a "$LOG_FILE"

# Apply cooldown on manual close only if guard did not trigger
if [ -f "$GUARD_KILL_FILE" ]; then
    rm "$GUARD_KILL_FILE"
else
    echo "$(date +%s)" > "$COOLDOWN_FILE"
    echo 300 > "$COOLDOWN_DURATION_FILE"
fi
