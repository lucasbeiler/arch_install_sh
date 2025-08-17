local wezterm = require 'wezterm';

return {

  font = wezterm.font("Fantasque Sans Mono", {weight="Medium", stretch="Normal", style="Normal"}),  
  window_decorations = "INTEGRATED_BUTTONS|RESIZE",
  font_size = 12.0,

  window_padding = {
    left = 25,
    right = 25,
    top = 15,
    bottom = 15,
  },

  default_cursor_style = "SteadyBar",
  window_background_opacity = 0.84
}

