# Set the in_block flag when the block starts
/^{/ { in_block = 1 }
/}$/ { in_block = 0 }

in_block && /Game[[:space:]]+csgo\/addons\/metamod/ {
    line_present = 1
    print
    next
}

in_block && /Game_LowViolence[[:space:]]+csgo_lv/ && !line_present {
    print
    inserted = 1
    next
}

inserted && !line_present {
    printf "                        Game    csgo/addons/metamod\n"
    line_present 1
    inserted = 0
}

{ print }