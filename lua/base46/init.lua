local M = {}
local g = vim.g
local base46_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

M.opts = {
  ------------------------------- base46 -------------------------------------
  base46_cache = vim.fn.stdpath("data") .. "/base46/",
  nvchad_theme = "onedark",

  -- hl = highlights
  hl_add = {},
  hl_override = {},
  changed_themes = {},
  -- theme_toggle = { "onedark", "one_light" },
  -- theme = "onedark", -- default theme
  transparency = false,
  lsp_semantic_tokens = false, -- needs nvim v0.9, just adds highlight groups for lsp semantic tokens

  -- https://github.com/NvChad/base46/tree/v2.0/lua/base46/extended_integrations
  extended_integrations = {}, -- these aren't compiled by default, ex: "alpha", "notify"

  -- cmp themeing
  cmp = {
    icons = true,
    lspkind_text = true,
    style = "default", -- default/flat_light/flat_dark/atom/atom_colored
    border_color = "grey_fg", -- only applicable for "default" style, use color names from base30 variables
    selected_item_bg = "colored", -- colored / simple
  },

  telescope = { style = "borderless" }, -- borderless / bordered

  statusline = {
    theme = "default", -- default/vscode/vscode_colored/minimal
    -- default/round/block/arrow separators work only for default statusline theme
    -- round and block will work for minimal theme only
    separator_style = "default",
    overriden_modules = nil,
  },

  cheatsheet = { theme = "grid" },
}

M.setup = function(options)
  M.opts = vim.tbl_deep_extend("force", M.opts, options or {})
end

M.get_theme_tb = function(type)
  local default_path = "base46.themes." .. M.opts.nvchad_theme
  local user_path = "custom.themes." .. M.opts.nvchad_theme

  local present1, default_theme = pcall(require, default_path)
  local present2, user_theme = pcall(require, user_path)

  if present1 then
    return default_theme[type]
  elseif present2 then
    return user_theme[type]
  else
    error "No such theme!"
  end
end

M.merge_tb = function(...)
  return vim.tbl_deep_extend("force", ...)
end

local change_hex_lightness = require("base46.colors").change_hex_lightness

-- turns color var names in hl_override/hl_add to actual colors
-- hl_add = { abc = { bg = "one_bg" }} -> bg = colors.one_bg
M.turn_str_to_color = function(tb)
  local colors = M.get_theme_tb "base_30"
  local copy = vim.deepcopy(tb)

  for _, hlgroups in pairs(copy) do
    for opt, val in pairs(hlgroups) do
      if opt == "fg" or opt == "bg" or opt == "sp" then
        if not (type(val) == "string" and val:sub(1, 1) == "#" or val == "none" or val == "NONE") then
          hlgroups[opt] = type(val) == "table" and change_hex_lightness(colors[val[1]], val[2]) or colors[val]
        end
      end
    end
  end

  return copy
end

M.extend_default_hl = function(highlights)
  local polish_hl = M.get_theme_tb "polish_hl"

  -- polish themes
  if polish_hl then
    for key, value in pairs(polish_hl) do
      if highlights[key] then
        highlights[key] = M.merge_tb(highlights[key], value)
      end
    end
  end

  -- transparency
  if M.opts.transparency then
    local glassy = require "base46.glassy"

    for key, value in pairs(glassy) do
      if highlights[key] then
        highlights[key] = M.merge_tb(highlights[key], value)
      end
    end
  end

  if M.opts.hl_override then
    local overriden_hl = M.turn_str_to_color(M.opts.hl_override)

    for key, value in pairs(overriden_hl) do
      if highlights[key] then
        highlights[key] = M.merge_tb(highlights[key], value)
      end
    end
  end
end

M.load_highlight = function(group)
  group = require("base46.integrations." .. group)
  M.extend_default_hl(group)
  return group
end

-- convert table into string
M.table_to_str = function(tb)
  local result = ""

  for hlgroupName, hlgroup_vals in pairs(tb) do
    local hlname = "'" .. hlgroupName .. "',"
    local opts = ""

    for optName, optVal in pairs(hlgroup_vals) do
      local valueInStr = ((type(optVal)) == "boolean" or type(optVal) == "number") and tostring(optVal)
        or '"' .. optVal .. '"'
      opts = opts .. optName .. "=" .. valueInStr .. ","
    end

    result = result .. "vim.api.nvim_set_hl(0," .. hlname .. "{" .. opts .. "})"
  end

  return result
end

M.saveStr_to_cache = function(filename, tb)
  -- Thanks to https://github.com/nullchilly and https://github.com/EdenEast/nightfox.nvim
  -- It helped me understand string.dump stuff

  local bg_opt = "vim.opt.bg='" .. M.get_theme_tb "type" .. "'"
  local defaults_cond = filename == "defaults" and bg_opt or ""

  local lines = "return string.dump(function()" .. defaults_cond .. M.table_to_str(tb) .. "end, true)"
  local file = io.open(M.opts.base46_cache .. filename, "wb")

  if file then
    file:write(loadstring(lines)())
    file:close()
  end
end

M.compile = function()
  if not vim.loop.fs_stat(M.opts.base46_cache) then
    vim.fn.mkdir(M.opts.base46_cache, "p")
  end

  -- All integration modules, each file returns a table
  local hl_files = base46_path .. "/integrations"

  for _, file in ipairs(vim.fn.readdir(hl_files)) do
    -- skip caching some files
    if file ~= "statusline" or file ~= "treesitter" then
      local filename = vim.fn.fnamemodify(file, ":r")
      M.saveStr_to_cache(filename, M.load_highlight(filename))
    end
  end

  -- look for custom cached highlight files
  local extended_integrations = M.opts.extended_integrations

  if extended_integrations then
    for _, integration in ipairs(extended_integrations) do
      M.saveStr_to_cache(integration, require("base46.extended_integrations." .. integration))
    end
  end
end

M.load_all_highlights_without_compile = function()
  require("plenary.reload").reload_module "base46"

  for _, file in ipairs(vim.fn.readdir(M.opts.base46_cache)) do
    dofile(M.opts.base46_cache .. file)
  end
end


M.load_all_highlights = function()
  require("plenary.reload").reload_module "base46"
  M.compile()

  for _, file in ipairs(vim.fn.readdir(M.opts.base46_cache)) do
    dofile(M.opts.base46_cache .. file)
  end
end

M.override_theme = function(default_theme, theme_name)
  local changed_themes = M.opts.changed_themes
  return M.merge_tb(default_theme, changed_themes.all or {}, changed_themes[theme_name] or {})
end

-- M.toggle_theme = function()
--   local themes = M.opts.theme_toggle
--   local theme1 = themes[1]
--   local theme2 = themes[2]

--   if M.opts.nvchad_theme ~= theme1 and M.opts.nvchad_theme ~= theme2 then
--     vim.notify "Set your current theme to one of those mentioned in the theme_toggle table (chadrc)"
--     return
--   end

--   if M.opts.nvchad_theme == theme1 then
--     g.toggle_theme_icon = "   "
--     vim.M.opts.nvchad_theme = theme2
--     require("nvchad").replace_word('theme = "' .. theme1, 'theme = "' .. theme2)
--   else
--     vim.M.opts.nvchad_theme = theme1
--     g.toggle_theme_icon = "   "
--     require("nvchad").replace_word('theme = "' .. theme2, 'theme = "' .. theme1)
--   end

--   M.load_all_highlights()
-- end

M.toggle_transparency = function()
  g.transparency = not g.transparency
  M.load_all_highlights()

  -- write transparency value to chadrc
  local old_data = "transparency = " .. tostring(M.opts.transparency)
  local new_data = "transparency = " .. tostring(g.transparency)

  require("nvchad").replace_word(old_data, new_data)
end

M.create_color_files = function()
    local path = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])"):sub(1, -2)
    local color_dir = path .. "/../../colors"

    if vim.fn.isdirectory(color_dir) then
        vim.fn.delete(color_dir, "rf")
    end

    vim.fn.mkdir(color_dir, "p")

    for _, file in ipairs(vim.fn.readdir(path .. "/themes")) do
        if vim.fn.isdirectory(path .. "/" .. file) == 0 and not file:match "^%." then
            local name = file:gsub("%.lua$", "")
            local color_file = color_dir .. "/" .. "base46_" .. name .. ".lua"
            local content = string.format( "require \"base46\".setup({ nvchad_theme = \"%s\" })\n\nrequire(\"base46\").load_all_highlights()", name )
            local f = io.open(color_file, "w")
            f:write(content)
            f:close()
        end
    end
end

return M
