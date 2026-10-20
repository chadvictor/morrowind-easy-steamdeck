-- Original OpenMW UI overlay. The native helper owns input and field editing.
-- This layer is deliberately non-interactive: the game's EditBox keeps focus.
local ui = require('openmw.ui')
local util = require('openmw.util')
local core = require('openmw.core')
local templates = require('openmw.interfaces').MWUI.templates
local keys = require('scripts.mes.keyboard_layout')
local v2 = util.vector2
local rgb = util.color.rgb
local layerName = 'MESVirtualKeyboard'
local white = ui.texture { path = 'white' }
local panel, state, lastPacket, lastSize
local stamp = ''
local layerRequested = false

local function close()
    if panel then panel:destroy(); panel = nil end
    state, lastSize, stamp = nil, nil, ''
end

local function layerSize()
    local index = ui.layers.indexOf(layerName)
    if not index then
        -- Above modals/notifications, without becoming a modal or picking input.
        if not layerRequested then
            ui.layers.insertAfter('Notification', layerName, { interactive = false })
            layerRequested = true
        end
        -- Layer insertion is queued on the UI thread; it appears next frame.
        return nil
    end
    return ui.layers[index].size
end

local function text(value, x, y, w, h, size, color)
    return {
        type = ui.TYPE.Text,
        template = templates.textNormal,
        props = {
            text = value, position = v2(x, y), size = v2(w, h),
            textSize = size, textColor = color,
            textAlignH = ui.ALIGNMENT.Center, textAlignV = ui.ALIGNMENT.Center,
            autoSize = false,
        },
    }
end

local function fill(x, y, w, h, color)
    return { type = ui.TYPE.Image, props = {
        resource = white, position = v2(x, y), size = v2(w, h), color = color,
    } }
end

local function render()
    local screen = layerSize()
    if not screen then return end
    local width = math.min(screen.x - 16, 1040)
    local rowHeight = math.max(24, math.min(38, screen.y * 0.052))
    local titleHeight, footerHeight = 44, 44
    local height = rowHeight * 5 + titleHeight + footerHeight + 16
    local font = math.max(14, math.min(20, rowHeight * 0.58))
    local unit = (width - 20) / 15
    local content = {
        fill(0, 0, width, height, rgb(0.055, 0.045, 0.035)),
        { template = templates.bordersThick, props = { size = v2(width, height) } },
        text('US QWERTY  |  ' .. (state.active and 'Typing into the selected field' or 'Select a text field to type'),
            8, 5, width - 16, 22, math.min(font, 18), rgb(0.92, 0.82, 0.62)),
        text('Shift: ' .. (state.shift and 'ON' or 'off') .. '   Caps: ' .. (state.caps and 'ON' or 'off'),
            8, 25, width - 16, 18, math.min(font, 16), rgb(0.72, 0.69, 0.62)),
    }
    for index, key in ipairs(keys) do
        local selected = index == state.selected
        local x, y = 10 + key.x * unit, titleHeight + key.row * rowHeight + 4
        local w, h = key.width * unit - 4, rowHeight - 4
        local label = key.label
        if key.action == 'text' then
            local letter = key.label:match('^[a-z]$') ~= nil
            local upper = state.shift
            if letter and state.caps then upper = not upper end
            if upper then label = key.shifted end
            -- MyGUI treats '#' as colour markup; double it to draw a literal.
            label = label:gsub('#', '##')
        end
        content[#content + 1] = fill(x, y, w, h,
            selected and rgb(0.72, 0.55, 0.27) or rgb(0.15, 0.13, 0.10))
        content[#content + 1] = text(label, x, y, w, h,
            math.min(font, key.width >= 1.5 and 18 or font),
            selected and rgb(0.04, 0.035, 0.025) or rgb(0.90, 0.84, 0.70))
    end
    local footerY = titleHeight + rowHeight * 5 + 5
    content[#content + 1] = text('D-pad / stick: move   A: type   X: erase   Y: Shift   B: close',
        8, footerY, width - 16, 20, math.min(font, 16), rgb(0.87, 0.82, 0.70))
    content[#content + 1] = text('LB / RB: text cursor   Enter: confirm   Done: close without confirming',
        8, footerY + 20, width - 16, 20, math.min(font, 15), rgb(0.72, 0.69, 0.62))
    local layout = {
        type = ui.TYPE.Widget, layer = layerName,
        props = { position = v2((screen.x - width) / 2, screen.y - height - 8), size = v2(width, height) },
        content = ui.content(content),
    }
    if panel then panel.layout = layout; panel:update()
    else panel = ui.create(layout) end
    lastSize = { x = screen.x, y = screen.y }
end

local function onKeyRelease(event)
    -- Reserved non-printable SDL releases cannot become remapping captures.
    if not event.withSuper then return end
    if event.code == 499 then close(); return end
    local selected = event.code - 400 + 1
    if selected < 1 or selected > #keys then return end
    lastPacket = core.getRealTime()
    local nextStamp = tostring(selected) .. tostring(event.withShift) ..
        tostring(event.withCtrl) .. tostring(event.withAlt)
    state = { selected = selected, shift = event.withShift, caps = event.withCtrl, active = event.withAlt }
    if nextStamp ~= stamp or not panel then
        stamp = nextStamp
        render()
    end
end

local function onFrame()
    if not state then return end
    -- Real time works in paused menus. A stale overlay must not cover the UI.
    if core.getRealTime() - lastPacket > 3 then close(); return end
    local screen = layerSize()
    if screen and (not panel or screen.x ~= lastSize.x or screen.y ~= lastSize.y) then render() end
end

return {
    engineHandlers = { onKeyRelease = onKeyRelease, onFrame = onFrame, onStateChanged = close },
}
