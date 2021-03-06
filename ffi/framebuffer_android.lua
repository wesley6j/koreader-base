local ffi = require("ffi")
local android = require("android")
local BB = require("ffi/blitbuffer")
local C = ffi.C

--[[ configuration for devices with an electric paper display controller ]]--

-- does the device has an e-ink screen?
local has_eink_screen, eink_platform = android.isEink()

-- does the device needs to handle all screen refreshes
local has_eink_full_support = android.isEinkFull()

-- for *some* rockchip devices
local rk_full, rk_partial, rk_a2, rk_auto = 1, 2, 3, 4 -- luacheck: ignore

-- for *some* freescale devices
local ntx_du, ntx_gc16, ntx_auto, ntx_regal, ntx_full = 1, 2, 5, 7, 34 -- luacheck: ignore

-- update a region of the screen
local function updatePartial(mode, delay, x, y, w, h)
    if not (x and y and w and h) then
        x = 0
        y = 0
        w = android.screen.width
        h = android.screen.height
    end
    if x < 0 then x = 0 end
    if y < 0 then y = 0 end
    if (x + w) > android.screen.width then w = android.screen.width - x end
    if (y + h) > android.screen.height then h = android.screen.height - y end

    android.einkUpdate(mode, delay, x, y, (x + w), (y + h))
end

-- update the entire screen
local function updateFull()
    -- freescale ntx platform
    if has_eink_screen and (eink_platform == "freescale") then
        if has_eink_full_support then
            -- we handle the screen entirely. Add a delay before a full update.
            updatePartial(ntx_full, 50)
        else
            -- we're racing against system driver, update without delay to avoid artifacts
            updatePartial(ntx_full, 0)
        end
    -- rockchip rk3x platform
    elseif has_eink_screen and (eink_platform == "rockchip") then
        android.einkUpdate(rk_full)
    end
end

local framebuffer = {}

function framebuffer:init()
    -- we present this buffer to the outside
    self.bb = BB.new(android.screen.width, android.screen.height, BB.TYPE_BBRGB32)
    self.invert_bb = BB.new(android.screen.width, android.screen.height, BB.TYPE_BBRGB32)
    -- TODO: should we better use these?
    -- android.lib.ANativeWindow_getWidth(window)
    -- android.lib.ANativeWindow_getHeight(window)
    self.bb:fill(BB.COLOR_WHITE)
    self:_updateWindow()

    framebuffer.parent.init(self)
end

function framebuffer:_updateWindow()
    if android.app.window == nil then
        android.LOGW("cannot blit: no window")
        return
    end

    local buffer = ffi.new("ANativeWindow_Buffer[1]")
    if android.lib.ANativeWindow_lock(android.app.window, buffer, nil) < 0 then
        android.LOGW("Unable to lock window buffer")
        return
    end

    local bb = nil
    if buffer[0].format == C.WINDOW_FORMAT_RGBA_8888
    or buffer[0].format == C.WINDOW_FORMAT_RGBX_8888
    then
        bb = BB.new(buffer[0].width, buffer[0].height, BB.TYPE_BBRGB32, buffer[0].bits, buffer[0].stride*4, buffer[0].stride)
    elseif buffer[0].format == C.WINDOW_FORMAT_RGB_565 then
        bb = BB.new(buffer[0].width, buffer[0].height, BB.TYPE_BBRGB16, buffer[0].bits, buffer[0].stride*2, buffer[0].stride)
    else
        android.LOGE("unsupported window format!")
    end

    if bb then
        local ext_bb = self.full_bb or self.bb

        bb:setInverse(ext_bb:getInverse())
        -- adapt to possible rotation changes
        bb:setRotation(ext_bb:getRotation())
        self.invert_bb:setRotation(ext_bb:getRotation())

        if ext_bb:getInverse() == 1 then
            self.invert_bb:invertblitFrom(ext_bb)
            bb:blitFrom(self.invert_bb)
        else
            bb:blitFrom(ext_bb)
        end
    end

    android.lib.ANativeWindow_unlockAndPost(android.app.window);
end

function framebuffer:refreshFullImp(x, y, w, h)
    self:_updateWindow()
    updateFull()
end

function framebuffer:refreshPartialImp(x, y, w, h)
    self:_updateWindow()
    if has_eink_full_support then
        updatePartial(ntx_auto, 0, x, y, w, h)
    end
end

function framebuffer:refreshFlashPartialImp(x, y, w, h)
    self:_updateWindow()
    if has_eink_full_support then
        updatePartial(ntx_gc16, 0, x, y, w, h)
    end
end

function framebuffer:refreshUIImp(x, y, w, h)
    self:_updateWindow()
    if has_eink_full_support then
        updatePartial(ntx_auto, 0, x, y, w, h)
    end
end

function framebuffer:refreshFlashUIImp(x, y, w, h)
    self:_updateWindow()
    if has_eink_full_support then
        updatePartial(ntx_gc16, 0, x, y, w, h)
    end
end

function framebuffer:refreshFastImp(x, y, w, h)
    self:_updateWindow()
    if has_eink_full_support then
        updatePartial(ntx_du, 0, x, y, w, h)
    end
end

return require("ffi/framebuffer"):extend(framebuffer)
