#!/bin/zsh
#
# activate-reports.zsh — https://github.com/madebywindmill/asc-tools
#
# Asks Apple to start making App Store Connect analytics reports for your apps.
# Apple only lets an Admin key do this, and only through its API.
#
# The key file is only read, in its existing location, by Apple's own `openssl` to
# sign a short-lived token. It's never copied, moved, saved, or sent. Only the
# token goes out, and only to api.appstoreconnect.apple.com.
#
# Every option is optional; anything missing is asked for.
#   --key <path>          Key file (AuthKey_XXXXXXXXXX.p8). Admin to activate; see --check.
#   --key-id <id>         Key ID, if it isn't in the file name
#   --issuer <id>         Issuer ID (App Store Connect › Users and Access › Integrations)
#   --app <id>[=<name>]   An app to activate; repeat for more. Without it, you pick from all your apps.
#   --new-history <id>    Request past data for this app even if an older request exists.
#                         The app is included even without --app.
#   --check               Only show each app's report status; change nothing.
#                         Works with an Admin, Sales and Reports, or Finance key.
#   --forget-issuer       Delete the issuer ID this tool remembered, then quit
#
# The only thing this tool ever saves is your issuer ID, and only if you say
# yes when it asks. It's kept with `defaults` under com.madebywindmill.asc-tools.

emulate -L zsh
setopt no_unset pipe_fail

readonly API="https://api.appstoreconnect.apple.com/v1"
readonly REPO="https://github.com/madebywindmill/asc-tools"
readonly PREFS="com.madebywindmill.asc-tools"

key_file="" key_id="" issuer="" token="" check=0 typed_issuer=0 saved_issuer=0
typeset -aU app_ids new_history
typeset -A app_names

work=$(/usr/bin/mktemp -d) || exit 1
trap '/bin/rm -rf "$work"' EXIT
body="$work/body.json"

# ---- Helpers ---------------------------------------------------------------

say()  { print -r -- "$@" }
fail() { print -r -- "✗ $*" >&2; exit 1 }

# Prompts read from the keyboard even when the script itself arrived on stdin.
ask() { local answer; read -r "answer?$1" < /dev/tty; REPLY=$answer }

b64url() { /usr/bin/base64 | /usr/bin/tr '+/' '-_' | /usr/bin/tr -d '=\n' }

# Reads one value from the last response, e.g. json data.0.attributes.name
json() { /usr/bin/plutil -extract "$1" raw -o - "$body" 2>/dev/null }

# Makes an App Store Connect request. Sets $http; the response is in $body.
# The token goes in a header read from a pipe, so it never shows in `ps`.
call() {
    local method=$1 path=$2 data=${3:-}
    local -a extra
    make_token
    [[ -n $data ]] && extra=(-H "Content-Type: application/json" --data-binary "$data")
    http=$(/usr/bin/curl -sS -o "$body" -w '%{http_code}' -X "$method" \
        -H @<(print -r -- "Authorization: Bearer $token") "${extra[@]}" "$API/$path") || http=000
}

revoke_reminder() {
    say "If you made this Admin key just for this, you can revoke it now in"
    say "App Store Connect › Users and Access › Integrations."
}

# Offers to remember an issuer ID the user typed, once Apple has accepted it.
finish() {
    if (( typed_issuer )); then
        say ""
        ask "Remember this issuer ID for next time? (y/n) "
        if [[ $REPLY == [yY]* ]]; then
            /usr/bin/defaults write $PREFS issuerID -string "$issuer"
            say "Saved. To forget it, run this tool with --forget-issuer."
        fi
    fi
    exit 0
}

apple_error() {
    json errors.0.detail || json errors.0.title || print "HTTP $http"
    if [[ $http == 401 && $saved_issuer == 1 ]]; then
        print "(This used your saved issuer ID. If it’s wrong, run with --forget-issuer.)"
    fi
}

# ---- Options ---------------------------------------------------------------

while (( $# )); do
    if [[ $1 == --(key|key-id|issuer|app|new-history) ]] && (( $# < 2 )); then
        fail "$1 needs a value."
    fi
    case $1 in
        --key)          key_file=$2; shift ;;
        --key-id)       key_id=$2; shift ;;
        --issuer)       issuer=$2; shift ;;
        --app)          app_ids+=(${2%%=*}); [[ $2 == *=* ]] && app_names[${2%%=*}]=${2#*=}; shift ;;
        --new-history)  new_history+=($2); app_ids+=($2); shift ;;
        --check)        check=1 ;;
        --forget-issuer)
            /usr/bin/defaults delete $PREFS issuerID 2>/dev/null
            say "The saved issuer ID is gone."; exit 0 ;;
        *)              fail "Unknown option: $1" ;;
    esac
    shift
done

for id in $app_ids $new_history; do
    [[ $id == <-> ]] || fail "“$id” isn’t an app ID. App IDs are all digits."
done

# ---- Introduction ----------------------------------------------------------

say ""
if (( check )); then
    say "Check App Store analytics reports"
    say ""
    say "This small open-source tool checks whether Apple is making analytics"
    say "reports for your apps. It only looks and changes nothing. It works with"
    say "a key that has the Admin, Sales and Reports, or Finance role."
    key_kind="key"
else
    say "Activate App Store analytics reports"
    say ""
    say "This small open-source tool asks Apple to start making analytics reports"
    say "for your apps. Apple requires an Admin key to do this."
    key_kind="Admin key"
fi
say ""
say "The tool only reads your $key_kind file, right where it is, to sign"
say "requests to Apple. It never copies, moves, saves, or sends the key."
say ""
say "Review the tool: $REPO"
say ""

# ---- The key ---------------------------------------------------------------

if [[ -z $key_file ]]; then
    say "Need a key? In App Store Connect, go to Users and Access › Integrations ›"
    say "App Store Connect API (https://appstoreconnect.apple.com/access/integrations/api)."
    if (( check )); then
        say "Generate a Team Key with the Admin, Sales and Reports, or Finance role,"
        say "then download its .p8 file."
    else
        say "Generate a Team Key with the Admin role, then download its .p8 file."
    fi
    say "Apple lets you download each key only once. Your issuer ID is on the same page."
    say ""
    ask "Drag your $key_kind file (AuthKey_….p8) here, then press Return: "
    # Dragging into Terminal escapes spaces; (Q) removes that quoting.
    key_file=${(Q)${REPLY%% #}}
fi
[[ -n $key_file ]] || fail "No key file given."
[[ $key_file == "~/"* ]] && key_file=$HOME/${key_file#\~/}
[[ -r $key_file ]] || fail "Can’t read the key file: $key_file"

if [[ -z $key_id && ${key_file:t} =~ '^AuthKey_([A-Z0-9]+)\.p8$' ]]; then
    key_id=$match[1]
fi
[[ -n $key_id ]] || { ask "Key ID: "; key_id=$REPLY }
if [[ -z $issuer ]]; then
    saved=$(/usr/bin/defaults read $PREFS issuerID 2>/dev/null)
    if [[ -n $saved ]]; then
        ask "Issuer ID (press Return to use your saved one, $saved): "
        if [[ -z $REPLY ]]; then
            issuer=$saved saved_issuer=1
        else
            issuer=$REPLY typed_issuer=1
        fi
    else
        ask "Issuer ID (App Store Connect › Users and Access › Integrations): "
        issuer=$REPLY typed_issuer=1
    fi
fi

[[ $key_id =~ '^[A-Z0-9]+$' ]] || fail "“$key_id” doesn’t look like a key ID."
[[ $issuer =~ '^[0-9a-fA-F-]+$' ]] || fail "“$issuer” doesn’t look like an issuer ID."

# ---- The token -------------------------------------------------------------

# A standard App Store Connect token (ES256 JWT), valid for 10 minutes. A new
# one is made for every request, so a long pause at a prompt doesn't matter.
make_token() {
    local now header claims integers r s signature
    local -a parts
    now=$(/bin/date +%s)
    header=$(print -rn -- "{\"alg\":\"ES256\",\"kid\":\"$key_id\",\"typ\":\"JWT\"}" | b64url)
    claims=$(print -rn -- "{\"iss\":\"$issuer\",\"iat\":$now,\"exp\":$((now + 600)),\"aud\":\"appstoreconnect-v1\"}" | b64url)

    # openssl signs in DER form; a JWT wants the two 32-byte numbers side by side.
    integers=$(print -rn -- "$header.$claims" \
        | /usr/bin/openssl dgst -sha256 -sign "$key_file" 2>/dev/null \
        | /usr/bin/openssl asn1parse -inform DER 2>/dev/null \
        | /usr/bin/sed -n 's/.*INTEGER *://p')
    parts=(${(f)integers})
    (( ${#parts} == 2 )) || fail "That file isn’t an App Store Connect key (.p8)."
    r=${(l:64::0:)parts[1]} s=${(l:64::0:)parts[2]}
    signature=$(print -rn -- "${r[-64,-1]}${s[-64,-1]}" | /usr/bin/xxd -r -p | b64url)
    token="$header.$claims.$signature"
}
make_token

# ---- Which apps ------------------------------------------------------------

if (( ! ${#app_ids} )); then
    call GET "apps?limit=200&fields%5Bapps%5D=name"
    [[ $http == 200 ]] || fail "Apple didn’t accept the key: $(apple_error)"
    count=$(json data)
    (( count )) || fail "This key can’t see any apps."
    say "Your apps:"
    for (( i = 0; i < count; i++ )); do
        id=$(json data.$i.id); app_ids+=($id); app_names[$id]=$(json data.$i.attributes.name)
        say "  $((i + 1)). $app_names[$id]"
    done
    ask "Press Return for all of them, or type numbers separated by spaces: "
    if [[ -n $REPLY ]]; then
        picked=()
        for n in ${=REPLY}; do
            [[ $n == <-> ]] && (( n >= 1 && n <= count )) || fail "“$n” isn’t on the list."
            picked+=($app_ids[n])
        done
        app_ids=($picked)
    fi
    say ""
fi

# ---- What each app needs ---------------------------------------------------

# Daily reports need a live ONGOING request; Apple stops one nobody has read
# in a while. History comes from a ONE_TIME_SNAPSHOT request. A repeat snapshot
# makes Apple regenerate every report, so one is only added when there's none
# or --new-history asks for it.
typeset -A needs daily_state history_state
for id in $app_ids; do
    if [[ -z ${app_names[$id]:-} ]]; then
        call GET "apps/$id?fields%5Bapps%5D=name"
        [[ $http == 200 ]] || fail "Couldn’t find app $id: $(apple_error)"
        app_names[$id]=$(json data.attributes.name)
    fi
    call GET "apps/$id/analyticsReportRequests?limit=200"
    if [[ $http == 403 ]]; then
        (( check )) && fail "This key lacks permission to get report status. Use a key with the Admin, Sales and Reports, or Finance role."
        fail "This key lacks permission to get report status. Use an Admin key."
    fi
    [[ $http == 200 ]] || fail "Couldn’t check $app_names[$id]: $(apple_error)"
    daily_state[$id]=off history_state[$id]=off
    count=$(json data)
    for (( i = 0; i < ${count:-0}; i++ )); do
        case $(json data.$i.attributes.accessType) in
            ONGOING)
                if [[ $(json data.$i.attributes.stoppedDueToInactivity) != true ]]; then
                    daily_state[$id]=on
                elif [[ ${daily_state[$id]} == off ]]; then
                    daily_state[$id]=stopped
                fi ;;
            ONE_TIME_SNAPSHOT) history_state[$id]=on ;;
        esac
    done
    needs[$id]=""
    [[ ${daily_state[$id]} != on ]] && needs[$id]+=" ONGOING"
    [[ ${history_state[$id]} != on ]] || (( ${new_history[(Ie)$id]} )) && needs[$id]+=" ONE_TIME_SNAPSHOT"
done

# ---- Check only ------------------------------------------------------------

if (( check )); then
    say "Report status:"
    all_on=1
    for id in $app_ids; do
        case ${daily_state[$id]} in
            on)      d="daily reports active" ;;
            stopped) d="daily reports stopped by Apple" ;;
            off)     d="daily reports inactive" ;;
        esac
        [[ ${history_state[$id]} == on ]] && h="past data requested" || h="past data not requested"
        if [[ ${daily_state[$id]} == on && ${history_state[$id]} == on ]]; then
            say "  ✓ $app_names[$id] — $d, $h"
        else
            say "  ✗ $app_names[$id] — $d, $h"; all_on=0
        fi
    done
    say ""
    say "Daily reports bring in new data every day. Past data is a one-time request;"
    say "Apple can take a few days to deliver it."
    say ""
    if (( all_on )); then
        say "All reports are active. Nothing was changed."
    else
        say "Nothing was changed. To activate the apps marked ✗, run this tool again"
        say "without --check, using an Admin key."
    fi
    finish
fi

say "Here’s the plan:"
todo=0
for id in $app_ids; do
    case ${needs[$id]} in
        " ONGOING ONE_TIME_SNAPSHOT") say "  • $app_names[$id] — activate daily reports and request past data"; todo=1 ;;
        " ONGOING")                   say "  • $app_names[$id] — activate daily reports"; todo=1 ;;
        " ONE_TIME_SNAPSHOT")         say "  • $app_names[$id] — request past data"; todo=1 ;;
        *)                            say "  ✓ $app_names[$id] — already active" ;;
    esac
done
say ""
if (( ! todo )); then
    say "Everything’s already active, so nothing needed changing. Apple is making"
    say "daily reports for these apps and has already been asked for their past data."
    say ""
    say "If an app’s reports were just activated, its first data usually arrives in 1–2 days."
    revoke_reminder
    finish
fi

ask "Go ahead? (y/n) "
[[ $REPLY == [yY]* ]] || { say "Nothing was changed."; finish }
say ""

# ---- Activate --------------------------------------------------------------

failed=0 succeeded=0
for id in $app_ids; do
    for type in ${=needs[$id]}; do
        [[ $type == ONGOING ]] && label="daily reports" || label="past data"
        [[ $type == ONGOING ]] && done_msg="daily reports active" || done_msg="past data requested"
        call POST analyticsReportRequests \
            "{\"data\":{\"type\":\"analyticsReportRequests\",\"attributes\":{\"accessType\":\"$type\"},\"relationships\":{\"app\":{\"data\":{\"type\":\"apps\",\"id\":\"$id\"}}}}}"
        case $http in
            201) say "  ✓ $app_names[$id] — $done_msg"; succeeded=1 ;;
            409) if [[ $type == ONGOING ]]; then
                     say "  ✗ $app_names[$id] — Apple kept its stopped daily reports request ($(apple_error))"; failed=1
                 else
                     say "  ✓ $app_names[$id] — $label already requested"; succeeded=1
                 fi ;;
            403) say "  ✗ $app_names[$id] — Apple refused. Is this an Admin key? ($(apple_error))"; failed=1 ;;
            *)   say "  ✗ $app_names[$id] — $label failed: $(apple_error)"; failed=1 ;;
        esac
    done
done

say ""
(( failed )) && say "Some requests failed; you can run this again safely."
(( succeeded )) && say "First data usually arrives in 1–2 days."
revoke_reminder
finish
