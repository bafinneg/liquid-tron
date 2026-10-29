[alias]
    ai = "!f() { msg=\"$($HOME/home-infra/machines/7800x/scripts/llm-commit-msg.sh)\"; rc=$?; if [ $rc -ne 0 ]; then echo \"llm-commit-msg.sh exited $rc; opening empty editor\" >&2; exec git commit -e; fi; exec git commit -e -m \"$msg\"; }; f"
