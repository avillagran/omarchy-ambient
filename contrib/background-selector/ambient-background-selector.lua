-- Open the selector for the active Ambient category.
hl.unbind("SUPER + CTRL + SPACE")
o.bind("SUPER + CTRL + SPACE", "Background selector (active mode)",
  '"$HOME/.local/bin/omarchy-ambient-background-select" current')
