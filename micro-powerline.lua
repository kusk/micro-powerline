-- Micro-powerline by Anders Kusk https://github.com/kusk/micro-powerline
VERSION = "1.0.0"

local micro    = import("micro")
local buffer   = import("micro/buffer")
local config   = import("micro/config")
local shell    = import("micro/shell")
local filepath = import("filepath")
local strings  = import("strings")

-- Powerline/Nerd Font glyphs encoded as UTF-8 byte sequences (Lua decimal escapes).
-- Requires a Powerline-patched or Nerd Font terminal font.
local GL_RSEP   = "\238\130\176"  -- U+E0B0  solid right arrow
local GL_RTHIN  = "\238\130\177"  -- U+E0B1  thin  right arrow
local GL_LSEP   = "\238\130\178"  -- U+E0B2  solid left  arrow
local GL_LTHIN  = "\238\130\179"  -- U+E0B3  thin  left  arrow
local GL_BRANCH = "\238\130\160"  -- U+E0A0  git branch icon

-- Plain ASCII fallbacks used when powerline.patched_font = false
local AS_RSEP   = ">"
local AS_RTHIN  = "|"
local AS_LSEP   = "<"
local AS_LTHIN  = "|"
local AS_BRANCH = "#"

-- Git branch name cache: dir -> {value = string, expiry = number (unix ts)}
local _bcache    = {}
local BRANCH_TTL = 30  -- seconds between git queries per directory

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function usePF()
    return config.GetGlobalOption("powerline.patched_font") ~= false
end

local function applyFormat()
    if config.GetGlobalOption("powerline.override_format") == false then
        return
    end

    local rsep, lsep, lthin
    if usePF() then
        rsep  = GL_RSEP
        lsep  = GL_LSEP
        lthin = GL_LTHIN
    else
        rsep  = AS_RSEP
        lsep  = AS_LSEP
        lthin = AS_LTHIN
    end

    -- Left: 3 coloured segments separated by solid arrows.
    --   seg1: filename + modified / overwrite / paste indicators
    --   seg2: line:col cursor position
    --   seg3: git branch
    -- $(#name) switches the render style for everything that follows.
    -- $(#) at the end resets to the base statusline style for the fill area.
    config.SetGlobalOption("statusformatl",
        "$(#powerline.seg1) $(filename) $(modified)$(overwrite)$(status.paste)" ..
        "$(#powerline.sep1)" .. rsep ..
        "$(#powerline.seg2) $(line):$(col) " ..
        "$(#powerline.sep2)" .. rsep ..
        "$(#powerline.seg3) $(powerline.branch) " ..
        "$(#powerline.sep3)" .. rsep ..
        "$(#)"
    )

    -- Right: 2 coloured segments separated by solid left arrows.
    --   rseg1: percentage + encoding + fileformat (thin separators within)
    --   rseg2: filetype
    config.SetGlobalOption("statusformatr",
        "$(#powerline.rsep1)" .. lsep ..
        "$(#powerline.rseg2) $(percentage)% " ..
        "$(#powerline.rsep2)" .. lsep ..
        "$(#powerline.rseg3)" .. " $(opt:encoding) " ..
        "$(#powerline.rsep3)" .. lsep ..
        "$(#powerline.rseg5)" .. " $(opt:fileformat) " ..
        "$(#powerline.rsep4)" .. lsep ..
        "$(#powerline.rseg6) $(opt:filetype) "
    )
end

-------------------------------------------------------------------------------
-- Plugin entry point
-------------------------------------------------------------------------------

function init()
    -- Register options (values loaded from settings.json if present)
    config.RegisterGlobalOption("powerline", "patched_font",    true)
    config.RegisterGlobalOption("powerline", "override_format", true)
    config.RegisterGlobalOption("powerline", "show_branch",     true)

    -- Expose the git branch as a statusline token: $(powerline.branch)
    micro.SetStatusInfoFn("powerline.branch")

    -- Command to re-apply format strings after changing options at runtime
    config.MakeCommand("powerline.apply", cmdApply, config.NoComplete)

    applyFormat()
end

-- Re-apply format strings (useful after toggling options via :set)
function cmdApply(bp, args)
    applyFormat()
    micro.InfoBar():Message("Powerline: statusline format applied.")
end

-------------------------------------------------------------------------------
-- Status info function: $(powerline.branch)
-- Returns the git branch for the buffer's directory, cached for BRANCH_TTL s.
-------------------------------------------------------------------------------

function branch(b)
    if b == nil or b.Type.Kind == buffer.BTInfo then
        return ""
    end
    if b.Path == nil or b.Path == "" then
        return ""
    end
    if config.GetGlobalOption("powerline.show_branch") == false then
        return ""
    end

    local dir = filepath.Dir(b.Path)
    local now = os.time()
    local cached = _bcache[dir]

    if cached ~= nil and now < cached.expiry then
        return cached.value
    end

    local out, err = shell.ExecCommand(
        "git", "-C", dir, "rev-parse", "--abbrev-ref", "HEAD"
    )
    local v = ""
    if err == nil then
        local br = strings.TrimSpace(out)
        if br ~= "" and br ~= "HEAD" then
            local icon = usePF() and (GL_BRANCH .. " ") or "# "
            v = icon .. br
        end
    end

    _bcache[dir] = {value = v, expiry = now + BRANCH_TTL}
    return v
end

-------------------------------------------------------------------------------
-- Event hooks: keep the branch cache fresh
-------------------------------------------------------------------------------

-- Invalidate when a buffer is opened (user may have switched branches)
function onBufferOpen(buf)
    if buf ~= nil and buf.Path ~= nil and buf.Path ~= "" then
        _bcache[filepath.Dir(buf.Path)] = nil
    end
end

-- Invalidate after saving (commit/checkout during editing changes the branch)
function onSave(bp)
    if bp ~= nil and bp.Buf ~= nil then
        local p = bp.Buf.Path
        if p ~= nil and p ~= "" then
            _bcache[filepath.Dir(p)] = nil
        end
    end
end
