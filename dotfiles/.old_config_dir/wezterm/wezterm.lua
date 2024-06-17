local wezterm = require 'wezterm';

return {

  font = wezterm.font("Fantasque Sans Mono", {weight="Medium", stretch="Normal", style="Normal"}),  

  font_rules = {
    {
      italic = true,
      font = wezterm.font("Fantasque Sans Mono", {weight="Medium", stretch="Normal", style="Italic"}), 
    },
    {
      intensity = "Bold",
      font = wezterm.font("Fantasque Sans Mono", {weight="Bold", stretch="Normal", style="Normal"}),
    },
    {
      intensity = "Bold",
      italic = true,
      font = wezterm.font("Fantasque Sans Mono", {weight="Bold", stretch="Normal", style="Italic"})
    },
  },
  
  font_size = 12.0,
  
  color_scheme = "Catppuccin",
 
  colors = {
		indexed = {[16] = "#F8BD96", [17] = "#F5E0DC"},
		split = "#161320",
		visual_bell = "#302D41",
	},
  window_padding = {
    left = 25,
    right = 25,
    top = 15,
    bottom = 15,
  },

  default_cursor_style = "SteadyBar",
  window_background_opacity = 0.92,
  scrollback_lines = 5000,
  enable_scroll_bar = false,
  warn_about_missing_glyphs = false,
  check_for_updates = false,
}

