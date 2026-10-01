#!/usr/bin/env lua
-- powermenu - a small power menu (lock / logout / reboot / shutdown) for Hyprland.
--
-- Deps (Arch): sudo pacman -S lua-lgi gtk3 gtk-layer-shell
-- Keys: arrows/Tab move | Enter activate | L/E/R/S hotkeys | Esc or click outside closes

local lgi = require 'lgi'
local Gtk = lgi.require('Gtk', '3.0')
local Gdk = lgi.require('Gdk', '3.0')
local GLib = lgi.GLib
local LayerShell = lgi.require('GtkLayerShell', '0.1')

-- ---- tweak these -----------------------------------------------------------
local ICON_SIZE = 72            -- icon size in px
local BTN_WIDTH = 120           -- button width in px
local CONFIRM_DANGEROUS = false -- true = press twice to shutdown/reboot/logout

-- Order here is the order on screen. The first entry is selected by default,
-- so keep a harmless one (lock) first. `key` is the hotkey.
local ACTIONS = {
  { label = 'Shutdown', key = 's', icon = 'system-shutdown-symbolic',
    cmd = 'systemctl poweroff', danger = true },
  { label = 'Reboot',   key = 'r', icon = 'system-reboot-symbolic',
    cmd = 'systemctl reboot', danger = true },
  { label = 'Lock',     key = 'l', icon = 'system-lock-screen-symbolic',
    cmd = 'sh -c "hyprlock || swaylock -f || loginctl lock-session"' },
  { label = 'Logout',   key = 'e', icon = 'system-log-out-symbolic',
    cmd = 'hyprctl dispatch exit', danger = true },
  
  
}
-- ---------------------------------------------------------------------------

local CSS = string.format([[
window { background: transparent; }
#card {
    background: rgba(24, 24, 32, 0.92);
    border-radius: 22px;
    border: 2px solid rgba(255, 255, 255, 0.10);
    padding: 26px;
}
button.power-btn {
    background-image: none;
    background-color: rgba(255, 255, 255, 0.06);
    border: 2px solid transparent;
    border-radius: 18px;
    box-shadow: none;
    text-shadow: none;
    padding: 26px 10px;
    min-width: %dpx;
    color: #f0f0f5;
}
button.power-btn:hover { background-image: none; }
button.power-btn.selected {
    background-color: rgba(140, 170, 255, 0.25);
    border-color: rgba(140, 170, 255, 0.70);
}
button.power-btn.danger.selected {
    background-color: rgba(255, 110, 110, 0.25);
    border-color: rgba(255, 120, 120, 0.75);
}
button.power-btn image { color: #f0f0f5; }
.power-label { font-size: 16px; color: #f0f0f5; }
.power-hint { font-size: 12px; color: rgba(240, 240, 245, 0.45); }
.power-fallback { font-size: 56px; color: #f0f0f5; }
]], BTN_WIDTH)

-- GDK keysyms
local KEY = {
  Escape = 0xff1b, Return = 0xff0d, KP_Enter = 0xff8d, space = 0x20, Tab = 0xff09,
  ISO_Left_Tab = 0xfe20, Left = 0xff51, Up = 0xff52, Right = 0xff53, Down = 0xff54,
}

-- ---- window ----------------------------------------------------------------
local win = Gtk.Window { title = 'powermenu', app_paintable = true }
local visual = win:get_screen():get_rgba_visual()
if visual then win:set_visual(visual) end

-- layer-shell: full-screen overlay so clicks outside the card can close it
LayerShell.init_for_window(win)
LayerShell.set_layer(win, LayerShell.Layer.OVERLAY)
LayerShell.set_namespace(win, 'powermenu')
LayerShell.set_keyboard_mode(win, LayerShell.KeyboardMode.EXCLUSIVE)
LayerShell.set_exclusive_zone(win, -1)
for _, edge in ipairs { 'TOP', 'BOTTOM', 'LEFT', 'RIGHT' } do
  LayerShell.set_anchor(win, LayerShell.Edge[edge], true)
end

local provider = Gtk.CssProvider()
provider:load_from_data(CSS)
Gtk.StyleContext.add_provider_for_screen(
  Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

-- backdrop: click anywhere outside the card to close
local backdrop = Gtk.EventBox { visible_window = false }
function backdrop:on_button_press_event()
  Gtk.main_quit()
  return true
end
win:add(backdrop)

-- card wrapper swallows clicks on the card's padding; it does the centering
local card_wrap = Gtk.EventBox { visible_window = false, halign = 'CENTER', valign = 'CENTER' }
function card_wrap:on_button_press_event() return true end
backdrop:add(card_wrap)

local card = Gtk.Box { orientation = 'HORIZONTAL', spacing = 14, name = 'card' }
card_wrap:add(card)

-- ---- actions ---------------------------------------------------------------
local buttons = {}   -- { btn = Gtk.Button, label = Gtk.Label } per action
local sel = 1        -- selected action index
local pending = nil  -- action index waiting for a confirming second press

local function reset_pending()
  if pending then
    buttons[pending].label.label = ACTIONS[pending].label
    pending = nil
  end
end

local function select(i)
  if i == sel then return end
  reset_pending()
  buttons[sel].btn:get_style_context():remove_class('selected')
  sel = i
  buttons[sel].btn:get_style_context():add_class('selected')
end

local function run(a)
  local ok, err = pcall(GLib.spawn_command_line_async, a.cmd)
  if not ok then io.stderr:write('failed to run "' .. a.cmd .. '": ' .. tostring(err) .. '\n') end
  Gtk.main_quit()
end

local function activate(i)
  local a = ACTIONS[i]
  if CONFIRM_DANGEROUS and a.danger and pending ~= i then
    reset_pending()
    pending = i
    buttons[i].label.label = 'Press again'
    return
  end
  run(a)
end

local theme = Gtk.IconTheme.get_default()

for i, a in ipairs(ACTIONS) do
  local box = Gtk.Box { orientation = 'VERTICAL', spacing = 10 }

  if theme:lookup_icon(a.icon, ICON_SIZE, 0) then
    box:pack_start(Gtk.Image { icon_name = a.icon, pixel_size = ICON_SIZE }, false, false, 0)
  else -- no matching icon in the theme: show the first letter instead
    local fb = Gtk.Label { label = a.label:sub(1, 1) }
    fb:get_style_context():add_class('power-fallback')
    box:pack_start(fb, false, false, 0)
  end

  local label = Gtk.Label { label = a.label }
  label:get_style_context():add_class('power-label')
  box:pack_start(label, false, false, 0)

  local hint = Gtk.Label { label = a.key:upper() }
  hint:get_style_context():add_class('power-hint')
  box:pack_start(hint, false, false, 0)

  local btn = Gtk.Button { relief = 'NONE', can_focus = false }
  btn:add(box)
  local ctx = btn:get_style_context()
  ctx:add_class('power-btn')
  if a.danger then ctx:add_class('danger') end
  if i == sel then ctx:add_class('selected') end

  function btn:on_clicked() activate(i) end
  function btn:on_enter_notify_event()
    select(i)
    return false
  end

  card:pack_start(btn, false, false, 0)
  buttons[i] = { btn = btn, label = label }
end

-- ---- keyboard --------------------------------------------------------------
local function step(delta)
  select(((sel - 1 + delta) % #ACTIONS) + 1)
end

function win:on_key_press_event(ev)
  local k = ev.keyval
  if k == KEY.Escape then
    Gtk.main_quit()
  elseif k == KEY.Return or k == KEY.KP_Enter or k == KEY.space then
    activate(sel)
  elseif k == KEY.Right or k == KEY.Down or k == KEY.Tab then
    step(1)
  elseif k == KEY.Left or k == KEY.Up or k == KEY.ISO_Left_Tab then
    step(-1)
  elseif k < 256 then
    local ch = string.char(k):lower()
    for i, a in ipairs(ACTIONS) do
      if a.key == ch then
        select(i)
        activate(i)
        return true
      end
    end
    return false
  else
    return false
  end
  return true
end

function win:on_destroy() Gtk.main_quit() end

win:show_all()
Gtk.main()
