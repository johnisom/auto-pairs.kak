hook global ModuleLoaded auto-pairs %{
  auto-pairs-enable
}

provide-module auto-pairs %{

  # Options ────────────────────────────────────────────────────────────────────

  declare-option -docstring 'List of surrounding pairs' str-list auto_pairs ( ) { } [ ] '"' '"' "'" "'" ` ` “ ” ‘ ’ « » ‹ ›

  declare-option -hidden str auto_pairs_match_pair
  declare-option -hidden str auto_pairs_match_nestable_pair

  # Commands ───────────────────────────────────────────────────────────────────

  define-command auto-pairs-enable -docstring 'Enable auto-pairs' %{
    auto-pairs-set-option
    hook -group auto-pairs global InsertChar '\n' auto-pairs-new-line-inserted
    hook -group auto-pairs global InsertDelete '\n' auto-pairs-new-line-deleted
    hook -group auto-pairs global InsertChar ' ' auto-pairs-space-inserted
    hook -group auto-pairs global InsertDelete ' ' auto-pairs-space-deleted
    # Update auto-pairs on option changes
    hook -group auto-pairs global WinSetOption auto_pairs=.* auto-pairs-set-option
  }

  define-command auto-pairs-disable -docstring 'Disable auto-pairs' %{
    remove-hooks global 'auto-pairs|auto-pairs-.+'
  }

  # Option commands ────────────────────────────────────────────────────────────

  define-command -hidden auto-pairs-set-option %{
    # Clean hooks
    remove-hooks global auto-pairs-characters
    # Generate hooks for auto-paired characters.
    # Build regexes for matching a surrounding pair.
    evaluate-commands %sh{
      eval "set -- $kak_quoted_opt_auto_pairs"
      # Regexes
      match_pair=''
      match_nestable_pair=''
      while test $# -ge 2; do
        opening=$1 closing=$2
        shift 2
        # Let’s just pretend surrounding pairs can’t be cats [🐈🐱].
        if test "$opening" = "$closing"; then
          printf '
            hook -group auto-pairs-characters global InsertChar %%🐈\\Q%s\\E🐈 %%🐱auto-pairs-opening-or-closing-inserted %%🐈%s🐈🐱
            hook -group auto-pairs-characters global InsertDelete %%🐈\\Q%s\\E🐈 %%🐱auto-pairs-opening-or-closing-deleted %%🐈%s🐈🐱
          ' \
            "$opening" "$opening" \
            "$opening" "$opening"
        else
          printf '
            hook -group auto-pairs-characters global InsertChar %%🐈\\Q%s\\E🐈 %%🐱auto-pairs-opening-inserted %%🐈%s🐈 %%🐈%s🐈🐱
            hook -group auto-pairs-characters global InsertDelete %%🐈\\Q%s\\E🐈 %%🐱auto-pairs-opening-deleted %%🐈%s🐈 %%🐈%s🐈🐱
            hook -group auto-pairs-characters global InsertChar %%🐈\\Q%s\\E🐈 %%🐱auto-pairs-closing-inserted %%🐈%s🐈 %%🐈%s🐈🐱
            hook -group auto-pairs-characters global InsertDelete %%🐈\\Q%s\\E🐈 %%🐱auto-pairs-closing-deleted %%🐈%s🐈 %%🐈%s🐈🐱
          ' \
            "$opening" "$opening" "$closing" \
            "$opening" "$opening" "$closing" \
            "$closing" "$opening" "$closing" \
            "$closing" "$opening" "$closing"
          match_nestable_pair="$match_nestable_pair|(\\A\\Q$opening\\E\s*\\Q$closing\\E\\z)"
        fi
        match_pair="$match_pair|(\\A\\Q$opening\\E\s*\\Q$closing\\E\\z)"
      done
      # Set regex options
      match_pair=${match_pair#|}
      match_nestable_pair=${match_nestable_pair#|}
      printf 'set-option global auto_pairs_match_pair %s\n' "$match_pair"
      printf 'set-option global auto_pairs_match_nestable_pair %s\n' "$match_nestable_pair"
    }
  }

  # Implementation commands ────────────────────────────────────────────────────

  # ╭─────────────────────────────╮
  # │ What ┊ 0 ┊  1  ┊  2  ┊  3   │
  # ├─────────────────────────────┤
  # │  "   ┊ ▌ ┊ "▌" ┊ ""▌ ┊ """▌ │
  # ╰─────────────────────────────╯
  define-command -hidden auto-pairs-opening-or-closing-inserted -params 1 %{
    try %{
      # Case 2: Closing inserted
      auto-pairs-cursor-keep-fixed-string %arg{1}
      auto-pairs-closing-inserted %arg{1} %arg{1}
    } catch %{
      # Case 3: Skip post pair
      auto-pairs-cursor-reject-fixed-string %arg{1} '2h'
      # Case 1: Opening inserted
      # Skip if preceded by word characters
      # JoJo's Bizarre Adventure
      #    ‾ ‾
      auto-pairs-reject "\w\Q%arg{1}\E" 'hH'
      auto-pairs-opening-inserted %arg{1} %arg{1}
    } catch ''
  }

  # ╭────────────────────────╮
  # │ What ┊ 0 ┊  1  ┊   2   │
  # ├────────────────────────┤
  # │  (   ┊ ▌ ┊ (▌) ┊ ((▌)) │
  # ╰────────────────────────╯
  define-command -hidden auto-pairs-opening-inserted -params 2 %{
    try %{
      # Skip escaped pairs
      auto-pairs-cursor-reject-fixed-string '\' '2h'
      # Skip cursor under words
      # (JoJo
      #  ‾
      auto-pairs-cursor-reject '\w'
      # Insert the closing pair
      auto-pairs-insert-character-in-pair %arg{2}
    }
  }

  # ╭───────────────────────╮
  # │ What ┊ Input ┊ Output │
  # ├───────────────────────┤
  # │  )   ┊  (▌)  ┊  ()▌   │
  # ╰───────────────────────╯
  define-command -hidden auto-pairs-closing-inserted -params 2 %{
    try %{
      auto-pairs-cursor-keep-fixed-string %arg{2}
      execute-keys '<backspace>'
      auto-pairs-move-right-in-pair
    }
  }

  # ╭───────────────────────╮
  # │ What ┊ Input ┊ Output │
  # ├───────────────────────┤
  # │  ⌫   ┊  "▌"  ┊   ▌    │
  # ╰───────────────────────╯
  #
  # ╭───────────────────────╮
  # │ What ┊ Input ┊ Output │
  # ├───────────────────────┤
  # │  ⌫   ┊ ```▌  ┊  ``▌   │
  # ╰───────────────────────╯
  #
  # ╭───────────────────────╮
  # │ What ┊ Input ┊ Output │
  # ├───────────────────────┤
  # │  ⌫   ┊  ""▌  ┊   ▌    │
  # ╰───────────────────────╯
  define-command -hidden auto-pairs-opening-or-closing-deleted -params 1 %{
    try %{
      # Deleting in pair
      auto-pairs-cursor-keep-fixed-string %arg{1}
      auto-pairs-opening-deleted %arg{1} %arg{1}
    } catch %{
      # Deleting post pair
      # Skip full pairs
      auto-pairs-reject-fixed-string "%arg{1}%arg{1}" 'hH'
      # Delete opening pair
      auto-pairs-closing-deleted %arg{1} %arg{1}
    } catch ''
  }

  # ╭───────────────────────╮
  # │ What ┊ Input ┊ Output │
  # ├───────────────────────┤
  # │  ⌫   ┊  (▌)  ┊   ▌    │
  # ╰───────────────────────╯
  define-command -hidden auto-pairs-opening-deleted -params 2 %{
    try %{
      auto-pairs-cursor-keep-fixed-string %arg{2}
      execute-keys '<del>'
    }
  }

  # ╭───────────────────────╮
  # │ What ┊ Input ┊ Output │
  # ├───────────────────────┤
  # │  ⌫   ┊  ()▌  ┊   ▌    │
  # ╰───────────────────────╯
  define-command -hidden auto-pairs-closing-deleted -params 2 %{
    try %{
      auto-pairs-cursor-keep-fixed-string %arg{1} 'h'
      execute-keys '<backspace>'
    }
  }

  # ╭────────────────────────────────────────╮
  # │ What ┊      Input      ┊    Output     │
  # ├────────────────────────────────────────┤
  # │      ┊ void main() {▌} ┊ void main() { │
  # │  ⏎   ┊                 ┊   ▌           │
  # │      ┊                 ┊ }             │
  # ╰────────────────────────────────────────╯
  define-command -hidden auto-pairs-new-line-inserted %{
    try %{
      # Test a surrounding pair with the chunks of the previous line.
      auto-pairs-keep-surrounding-pair 'giKGl'
      # Copy previous line indent
      execute-keys -draft 'K<a-&>'
      # Insert a new line above
      execute-keys '<up><end><ret>'
      # And indent it
      execute-keys -draft 'K<a-&>j<a-gt>'
    }
  }

  # ╭────────────────────────────────────────╮
  # │ What ┊     Input     ┊     Output      │
  # ├────────────────────────────────────────┤
  # │      ┊ void main() { ┊ void main() {▌} │
  # │  ⌫   ┊ ▌             ┊                 │
  # │      ┊ }             ┊                 │
  # ╰────────────────────────────────────────╯
  define-command -hidden auto-pairs-new-line-deleted %{
    try %{
      # Test a surrounding pair with the chunks of the current and next lines.
      auto-pairs-keep-surrounding-pair ';<a-/>\H<ret>?\S<ret>'
      # Join surrounding pair
      execute-keys -draft '<a-a><space>d'
    }
  }

  # ╭──────────────────────────────╮
  # │ What ┊  0  ┊   1   ┊    2    │
  # ├──────────────────────────────┤
  # │  ␣   ┊ (▌) ┊ (␣▌␣) ┊ (␣␣▌␣␣) │
  # ╰──────────────────────────────╯
  define-command -hidden auto-pairs-space-inserted %{
    try %{
      # Test surrounding line content.
      auto-pairs-keep-nestable-pair ';<a-/>\H<ret>?\H<ret>'
      auto-pairs-insert-character-in-pair ' '
    }
  }

  # ╭──────────────────────────────╮
  # │ What ┊    0    ┊   1   ┊  2  │
  # ├──────────────────────────────┤
  # │  ⌫   ┊ (␣␣▌␣␣) ┊ (␣▌␣) ┊ (▌) │
  # ╰──────────────────────────────╯
  define-command -hidden auto-pairs-space-deleted %{
    try %{
      # Test surrounding line content.
      auto-pairs-keep-nestable-pair ';<a-/>\H<ret>?\H<ret>'
      execute-keys '<del>'
    }
  }

  # Utility commands ───────────────────────────────────────────────────────────

  define-command -hidden auto-pairs-keep-surrounding-pair -params ..1 %{
    auto-pairs-keep %opt{auto_pairs_match_pair} %arg{1}
  }

  define-command -hidden auto-pairs-keep-nestable-pair -params ..1 %{
    auto-pairs-keep %opt{auto_pairs_match_nestable_pair} %arg{1}
  }

  define-command -hidden auto-pairs-insert-character-in-pair -params 1 %{
    auto-pairs-insert-character %arg{1}
    # Jump backwards in pair, before inserting.
    auto-pairs-move-left-in-pair
  }

  define-command -hidden auto-pairs-insert-character -params 1 %{
    # A bit verbose, but more robust than passing text to execute-keys.
    evaluate-commands -save-regs '"' %{
      set-register '"' %arg{1}
      execute-keys '<c-r>"'
    }
  }

  # Move in pair
  define-command -hidden auto-pairs-move-left-in-pair %{
    auto-pairs-move-in-pair-implementation 'h' 'H'
  }
  define-command -hidden auto-pairs-move-right-in-pair %{
    auto-pairs-move-in-pair-implementation 'l' 'L'
  }
  define-command -hidden auto-pairs-move-in-pair-implementation -params 2 %{
    # If something is selected (i.e. the selection is not just the cursor),
    # preserve the anchor position.
    try %{
      # Test if extending
      execute-keys -draft '<a-k>.{2,}<ret>'
      # Preserve anchor position
      execute-keys '<a-;>' %arg{2}
    } catch %{
      # Jump without preserving
      execute-keys '<a-;>' %arg{1}
    }
  }

  # Keep
  define-command -hidden auto-pairs-keep-implementation -params 2..3 %{
    evaluate-commands -draft -save-regs '/' %{
      execute-keys %arg{3}
      set-register / %arg{2}
      execute-keys %arg{1} '<ret>'
    }
  }
  define-command -hidden auto-pairs-keep -params 1..2 %{
    auto-pairs-keep-implementation '<a-k>' %arg{@}
  }
  define-command -hidden auto-pairs-cursor-keep -params 1..2 %{
    auto-pairs-keep %arg{1} ";%arg{2}"
  }
  define-command -hidden auto-pairs-keep-fixed-string -params 1..2 %{
    auto-pairs-keep "\Q%arg{1}\E" %arg{2}
  }
  define-command -hidden auto-pairs-cursor-keep-fixed-string -params 1..2 %{
    auto-pairs-keep-fixed-string %arg{1} ";%arg{2}"
  }

  # Reject
  define-command -hidden auto-pairs-reject -params 1..2 %{
    auto-pairs-keep-implementation '<a-K>' %arg{@}
  }
  define-command -hidden auto-pairs-cursor-reject -params 1..2 %{
    auto-pairs-reject %arg{1} ";%arg{2}"
  }
  define-command -hidden auto-pairs-reject-fixed-string -params 1..2 %{
    auto-pairs-reject "\Q%arg{1}\E" %arg{2}
  }
  define-command -hidden auto-pairs-cursor-reject-fixed-string -params 1..2 %{
    auto-pairs-reject-fixed-string %arg{1} ";%arg{2}"
  }
}

require-module auto-pairs
