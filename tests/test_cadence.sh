#!/bin/sh
# When the model is asked: first substantial prompt, then every N-th (task 3.2).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/lib_refine.sh"
tmux_start
refine_setup

# step PROMPT EXPECTED_CALLS DESCRIPTION : send a prompt, let any evaluation finish, check the count.
step() {
    prompt "$1"
    if [ "$2" -gt "$(calls)" ]; then wait_calls_ge "$2"; fi
    settle
    assert_eq "$2" "$(calls)" "$3"
}

# --- trivial prompts never evaluate ---
new_session
step "/x" 0 "a slash command does not invoke the model"
step "corto" 0 "a prompt shorter than 10 characters does not invoke the model"
step "123456789" 0 "a 9-character prompt does not invoke the model"
step "/compact y un texto bastante largo" 0 "a long prompt starting with / does not invoke the model"
assert_eq "proj" "$(window_name)" "trivial prompts leave the name"

# --- default N = 3 ---
new_session
step "abcdefghij" 1 "1st substantial prompt (exactly 10 characters) invokes the model"
step "/x" 1 "trivial prompt after it does not invoke the model"
step "corto" 1 "another trivial prompt does not invoke the model"
step "segundo prompt sustancial" 1 "2nd substantial prompt does not invoke the model"
step "tercer prompt sustancial" 1 "3rd substantial prompt does not invoke the model"
step "cuarto prompt sustancial" 2 "4th substantial prompt invokes the model"
step "quinto prompt sustancial" 2 "5th substantial prompt does not invoke the model"
step "sexto prompt sustancial" 2 "6th substantial prompt does not invoke the model"
step "septimo prompt sustancial" 3 "7th substantial prompt invokes the model"
assert_eq "7" "$(opt @claude_n)" "@claude_n counts substantial prompts only"

# --- N = 1 evaluates every substantial prompt ---
new_session
export CLAUDE_TMUX_TITLE_EVERY=1
step "primer prompt sustancial" 1 "EVERY=1: 1st prompt invokes the model"
step "segundo prompt sustancial" 2 "EVERY=1: 2nd prompt invokes the model"
step "tercer prompt sustancial" 3 "EVERY=1: 3rd prompt invokes the model"
step "/x" 3 "EVERY=1: a trivial prompt still does not"

# --- N = 2 ---
new_session
export CLAUDE_TMUX_TITLE_EVERY=2
step "primer prompt sustancial" 1 "EVERY=2: 1st prompt invokes the model"
step "segundo prompt sustancial" 1 "EVERY=2: 2nd prompt does not"
step "tercer prompt sustancial" 2 "EVERY=2: 3rd prompt invokes the model"
finish
