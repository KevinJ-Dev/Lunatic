--[[
    https://github.com/overextended/ox_lib

    This file is licensed under LGPL-3.0 or higher <https://www.gnu.org/licenses/lgpl-3.0.en.html>

    Copyright © 2025 Linden <https://github.com/thelindat>
]]

---@class TextUIOptions
---@field position? 'right-center' | 'left-center' | 'top-center' | 'bottom-center';
---@field icon? string | {[1]: IconProp, [2]: string};
---@field iconColor? string;
---@field style? string | table;
---@field alignIcon? 'top' | 'center';

local isOpen = false
local currentText

-- Lunatic RP (modification locale) : textes [E] aux couleurs du panel staff, sauf si l'appelant donne son propre style
local LUNATIC_STYLE = {
    borderRadius = 10,
    backgroundColor = 'rgba(16, 12, 24, 0.9)',
    color = '#f3f1f7',
    border = '1px solid rgba(180, 138, 255, 0.45)',
    boxShadow = '0 10px 30px -12px rgba(0, 0, 0, 0.8), inset 0 0 0 1px rgba(150, 80, 255, 0.12)',
    fontWeight = 600,
}

---@param text string
---@param options? TextUIOptions
function lib.showTextUI(text, options)
    if currentText == text then return end

    if not options then options = {} end

    if options.style == nil then
        options.style = LUNATIC_STYLE
    end

    options.text = text
    currentText = text

    SendNUIMessage({
        action = 'textUi',
        data = options
    })

    isOpen = true
end

function lib.hideTextUI()
    SendNUIMessage({
        action = 'textUiHide'
    })

    isOpen = false
    currentText = nil
end

---@return boolean, string | nil
function lib.isTextUIOpen()
    return isOpen, currentText
end
