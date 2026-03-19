#!/bin/bash

# ============================================================
# FIREFOX GUARD
# A browser bouncer — session limiter + AI content filter
# ============================================================

MINUTES=$1
COOLDOWN_FILE="/home/$USER/.firefox_cooldown"
COOLDOWN_DURATION_FILE="/home/$USER/.firefox_cooldown_duration"
WORDLIST="$HOME/.config/firefox-guard/wordlist.txt"
PATTERNS="$HOME/.config/firefox-guard/patterns.txt"
PROMPT_FILE="$HOME/.config/firefox-guard/prompt.txt"

# ============================================================
# PREVENT MULTIPLE INSTANCES
# ============================================================
if pgrep -x "firefox" > /dev/null; then
    zenity --error --text="Firefox is already running." --title="Firefox Guard"
    exit 1
fi

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
/usr/lib/firefox/firefox "${@:2}" &
FF_PID=$!

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
    sleep 3  # give Firefox time to load
    while kill -0 $FF_PID 2>/dev/null; do
        sleep 1

        # Read current Firefox window title
        TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null)
        URL=$(echo "$TITLE" | grep -oP '(?<=— Mozilla Firefox).*' | xargs)

        # Extract search query from title if it's a Google search
        QUERY=$(echo "$TITLE" | sed 's/ - Google Search.*//' | sed 's/ — Mozilla Firefox.*//' | xargs)

        if [ -z "$QUERY" ] || [ "$QUERY" = "$LAST_QUERY" ]; then
            continue
        fi

        LAST_QUERY="$QUERY"

        # Layer 0 — Wordlist check
        if [ -f "$WORDLIST" ]; then
            while IFS= read -r word; do
                if echo "$QUERY" | grep -qi "$word"; then
                    zenity --error --text="Flagged search detected. 20 minute cooldown activated." --title="Firefox Guard" &
                    kill $FF_PID
                    echo "$(date +%s)" > "$COOLDOWN_FILE"
                    echo 1200 > "$COOLDOWN_DURATION_FILE"
                    exit 0
                fi
            done < "$WORDLIST"
        fi

        # Layer 1 — URL pattern check
        if [ -f "$PATTERNS" ]; then
            while IFS= read -r pattern; do
                if echo "$TITLE" | grep -qi "$pattern"; then
                    zenity --error --text="Flagged URL pattern detected. 20 minute cooldown activated." --title="Firefox Guard" &
                    kill $FF_PID
                    echo "$(date +%s)" > "$COOLDOWN_FILE"
                    echo 1200 > "$COOLDOWN_DURATION_FILE"
                    exit 0
                fi
            done < "$PATTERNS"
        fi

        # Layer 2 — Ollama AI check
        PROMPT=$(cat "$PROMPT_FILE" 2>/dev/null)
        RESPONSE=$(curl -s http://localhost:11434/api/chat -d "{
            \"model\": \"mistral\",
            \"messages\": [
                {\"role\": \"system\", \"content\": $(echo "$PROMPT" | jq -Rs .)},
                {\"role\": \"user\", \"content\": $(echo "Evaluate this search query: $QUERY" | jq -Rs .)}
            ],
            \"stream\": false
        }" | jq -r '.message.content' 2>/dev/null)

        if echo "$RESPONSE" | grep -qi "^YES"; then
            zenity --error --text="AI flagged your search. 20 minute cooldown activated." --title="Firefox Guard" &
            kill $FF_PID
            echo "$(date +%s)" > "$COOLDOWN_FILE"
            echo 1200 > "$COOLDOWN_DURATION_FILE"
            exit 0
        fi

    done
) &

# ============================================================
# WAIT FOR FIREFOX TO CLOSE
# ============================================================
wait $FF_PID

# Apply cooldown on manual close
echo "$(date +%s)" > "$COOLDOWN_FILE"
echo 300 > "$COOLDOWN_DURATION_FILE"
