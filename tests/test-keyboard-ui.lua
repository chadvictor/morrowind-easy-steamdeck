-- Run with LuaJIT/Lua 5.1. Native OpenMW rendering is checked separately.
package.path = 'assets/keyboard/?.lua;' .. package.path
local now, size = 0, { x=1024, y=640 }
local requested, installed, inserts, created, destroyed = false, false, 0, 0, 0
local current
local ui = {
    TYPE = { Widget='Widget', Text='Text', Image='Image' },
    ALIGNMENT = { Center='Center' },
    content = function(t) return t end,
    texture = function(t) return t end,
    layers = {},
}
ui.layers.indexOf = function() if installed then return 1 end end
ui.layers.insertAfter = function(after, name, options)
    assert(after == 'Notification' and name == 'MESVirtualKeyboard')
    assert(options.interactive == false, 'overlay must not capture native text focus')
    requested, inserts = true, inserts + 1
end
setmetatable(ui.layers, {__index=function(_, index)
    assert(index == 1 and installed, 'layer is not ready yet')
    return {size=size}
end})
ui.create = function(layout)
    created = created + 1
    current = {layout=layout}
    function current:update() end
    function current:destroy() destroyed = destroyed + 1; current=nil end
    return current
end
package.preload['openmw.ui'] = function() return ui end
package.preload['openmw.util'] = function() return {
    vector2=function(x,y) return {x=x,y=y} end,
    color={rgb=function(r,g,b) return {r=r,g=g,b=b} end},
} end
package.preload['openmw.core'] = function() return {getRealTime=function() return now end} end
package.preload['openmw.interfaces'] = function() return {MWUI={templates={textNormal={},bordersThick={}}}} end
local handlers = require('scripts.mes.keyboard').engineHandlers
local function packet(code, shift, caps, active)
    handlers.onKeyRelease {code=code,withSuper=true,withShift=shift or false,withCtrl=caps or false,withAlt=active or false}
end
local function labelContains(value)
    for _, child in ipairs(current.layout.content) do
        if child.props and child.props.text and child.props.text:find(value, 1, true) then return true end
    end
end
handlers.onKeyRelease {code=415,withSuper=false}
assert(not current and inserts == 0, 'ordinary releases must do nothing')
packet(399); packet(460)
assert(not current and inserts == 0, 'unknown protocol code must do nothing')
packet(415, false, false, true)
packet(415, false, false, true)
assert(requested and not current and inserts == 1, 'insertion must wait for UI thread once')
installed=true
handlers.onFrame()
assert(current and created == 1)
assert(labelContains('Typing into the selected field'))
for _, geometry in ipairs({{1280,800},{1024,640},{853,533},{640,480}}) do
    size={x=geometry[1],y=geometry[2]}
    handlers.onFrame()
    local p=current.layout.props
    assert(p.position.x >= 0 and p.position.y >= 0)
    assert(p.position.x + p.size.x <= size.x)
    assert(p.position.y + p.size.y <= size.y)
    local textCount=0
    for _, child in ipairs(current.layout.content) do
        assert(not child.events, 'keyboard visuals must not pick mouse/key focus')
        if child.type == 'Text' then
            textCount=textCount + 1
            assert(child.props.autoSize == false, 'fixed cells need centered text')
            assert(child.props.position.x + child.props.size.x <= p.size.x)
            assert(child.props.position.y + child.props.size.y <= p.size.y)
        end
    end
    assert(textCount == 64, '60 keys, two header and two footer lines')
end
packet(415, false, true, true)
assert(labelContains('Caps: ON') and labelContains('Q'))
packet(415, true, true, true)
assert(labelContains('q'), 'Shift and Caps must invert letter case')
packet(403, true, false, false)
assert(labelContains('##'), 'MyGUI literal hash needs escaping')
assert(labelContains('Select a text field'))
now=2; packet(403, true, false, false)
now=4; handlers.onFrame()
assert(current, 'unchanged heartbeat must keep the overlay alive')
now=6; handlers.onFrame()
assert(not current and destroyed == 1, 'stale overlay must close in paused menus')
packet(415)
assert(current)
packet(499)
assert(not current and destroyed == 2)
packet(415); handlers.onStateChanged()
assert(not current and destroyed == 3)
print('PASS: async layer, focus isolation, 60 keys, case, layout sizes, heartbeat, close and state reset')
