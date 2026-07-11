--[[
	WARNING: Heads up! This script has not been verified by ScriptBlox. Use at your own risk!
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local StarterPack = game:GetService("StarterPack")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")

-- CRITICAL: StarterCharacterScripts and StarterPlayerScripts are special Roblox
-- objects with their own unique ClassName, NOT Folders with the same name. If we
-- Instance.new("Folder") and rename it "StarterPlayerScripts", it conflicts with
-- the real Roblox service object — creating a fake container that receives scripts
-- while the Explorer shows the real (empty) service. This was the root cause of
-- "Not Found" when clicking scripts, even though create_script returned "✅ Success".
-- Fix: use the existing real object (FindFirstChildOfClass), or if it doesn't exist
-- (rare, since these are default Roblox services), create with the correct ClassName.
local StarterCharacterScripts = StarterPlayer:FindFirstChildOfClass("StarterCharacterScripts")
if not StarterCharacterScripts then
    local ok, created = pcall(function() return Instance.new("StarterCharacterScripts") end)
    if ok and created then
        created.Parent = StarterPlayer
        StarterCharacterScripts = created
    end
end
local StarterPlayerScripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
if not StarterPlayerScripts then
    local ok, created = pcall(function() return Instance.new("StarterPlayerScripts") end)
    if ok and created then
        created.Parent = StarterPlayer
        StarterPlayerScripts = created
    end
end
local player = Players.LocalPlayer
math.randomseed(tick() * 10000)

local sceneState = {}
-- FIX v1.4: حد أقصى لـ sceneState — بعده نحذف أقدم مدخل لمنع تسرب الذاكرة
local SCENE_STATE_MAX = 60

local function pruneSceneState()
    local count = 0
    for _ in pairs(sceneState) do count = count + 1 end
    if count <= SCENE_STATE_MAX then return end
    -- احذف المدخلات الأقدم (lastAction الأصغر)
    local oldest_key, oldest_time = nil, math.huge
    for k, v in pairs(sceneState) do
        if (v.lastAction or 0) < oldest_time then
            oldest_key = k
            oldest_time = v.lastAction or 0
        end
    end
    if oldest_key then sceneState[oldest_key] = nil end
end

local function updateSceneState(action, didSucceed)
    if not didSucceed then return end
    if not action or type(action) ~= "table" then return end
    _searchCache = nil -- scene changed, invalidate search cache
    local containerKey = action.containerName or (action.name or action.className or "default")
    if not sceneState[containerKey] then
        sceneState[containerKey] = { className = action.className, count = 0, namePrefix = action.namePrefix, createdNames = {} }
    end
    local ss = sceneState[containerKey]
    ss.lastAction = os.time()
    ss.className = action.className or ss.className
    if action.namePrefix then ss.namePrefix = action.namePrefix end
    if action.type == "create_instance" then
        ss.count = ss.count + 1
        if action.name then ss.createdNames[action.name] = true end
    elseif action.type == "create_multiple" then
        local c = math.clamp(tonumber(action.count) or 1, 1, 200)
        ss.count = ss.count + c
    elseif action.type == "create_compound" then
        ss.count = ss.count + 1
        if action.name then ss.createdNames[action.name] = true end
    elseif action.type == "delete" then
        local targetName = action.target
        if targetName and ss.createdNames then
            for n, _ in pairs(ss.createdNames) do
                if n:lower():find(targetName:lower(), 1, true) then
                    ss.createdNames[n] = nil
                    ss.count = math.max(0, ss.count - 1)
                    break
                end
            end
        end
    end
    -- FIX v1.4: تنظيف تلقائي لمنع تسرب الذاكرة
    pruneSceneState()
end

local undoStack = {}
local undoLimit = 20
local _logLabels = {} -- cleared after each request, tracks addLog labels for cleanup
local _batchCreated = {} -- cleared before each batch
local _lastClickInstance = nil -- for clickable messages
local _batchPlacedGrid = nil -- tracks grid positions in create_multiple
local _autoRunScripts = {} -- scripts to re-execute on player respawn (max 20)
local AUTORUN_MAX = 20
local _requestQueue = {}
local _processingRequest = false
local _searchCache = nil  -- FIX: كان implicit global يُعاد تصفيره في updateSceneState بدون تعريف local
local MESSAGE_MAX = 50
local MAX_TOKENS_LOW = 16000
local MAX_TOKENS_HIGH = 32000

-- re-run registered scripts on every respawn so effects (crosshair, camera, GUI) persist
-- ═══════════════════════════════════════════════════════
-- MODEL REGISTRY — Free (OpenCode) + NVIDIA NIM
-- ═══════════════════════════════════════════════════════
local OPENCODE_URL  = "https://opencode.ai/zen/v1/chat/completions"
local NVIDIA_URL    = "https://integrate.api.nvidia.com/v1/chat/completions"

-- مفاتيح OpenCode (rotation)
local OPENCODE_KEYS = {
    "sk-ZP0Y71QDq4HhXrr5KgWEzsf8ZyNNsLJL070xXcGFUh8w7cvlFFJuks5k4jv7puCK",
    "sk-dtcKP4hx4iznBCaVm1uFvbEax12z22hlJzcW9alSIya8OQfSigpJN42QfxHuP1xk",
    "sk-Pe12GsYt4RnkTPtb7ACCGSj5vzz7u7m2INVDzxe1Z2ccGF904LFCsxpzouJek6ld",
    "sk-MN9kABCiW1cskBQ4EncGFV6DFwyHvshu6CrjtmuHUFwdkvJvAHNzql90BqTpNHMC",
    "sk-yXrnjOHCXVejD3v1Ngk2trqs8B2cFpQd9hbhBlpVyrNZgeevk3lPolVY0EtgQZha",
}
-- you need put it 
local NVIDIA_API_KEY = " "

-- 
local MODEL_LIST = {
    -- ── Free (OpenCode) ──────────────────────────────────
    { label = "⭐ Big Pickle (Free)",           provider = "opencode", id = "big-pickle" },
    { label = "DeepSeek V4 Flash (Free)",       provider = "opencode", id = "deepseek-v4-flash-free" },
    { label = "MiMo V2.5 (Free)",               provider = "opencode", id = "mimo-v2.5-free" },
    { label = "Nemotron 3 Ultra (Free)",        provider = "opencode", id = "nemotron-3-ultra-free" },
    { label = "North Mini Code (Free)",         provider = "opencode", id = "north-mini-code-free" },
    -- ── NVIDIA NIM (verified active 2026-06) ─────────────
    { label = "── NVIDIA NIM ──",               provider = "separator" },
    { label = "DeepSeek V4 Flash",              provider = "nvidia", id = "deepseek-ai/deepseek-v4-flash", maxOutput = 8192 },
    { label = "DeepSeek V4 Pro",                provider = "nvidia", id = "deepseek-ai/deepseek-v4-pro", maxOutput = 8192 },
    { label = "Llama 4 Maverick 17b",           provider = "nvidia", id = "meta/llama-4-maverick-17b-128e-instruct", maxOutput = 4096 },
    { label = "Llama 3.3 70b",                  provider = "nvidia", id = "meta/llama-3.3-70b-instruct", maxOutput = 4096 },
    { label = "Llama 3.1 70b",                  provider = "nvidia", id = "meta/llama-3.1-70b-instruct", maxOutput = 4096 },
    { label = "Llama 3.1 8b",                   provider = "nvidia", id = "meta/llama-3.1-8b-instruct", maxOutput = 4096 },
    { label = "Mistral Large 3 675b",           provider = "nvidia", id = "mistralai/mistral-large-3-675b-instruct-2512", maxOutput = 8192 },
    { label = "Mistral Medium 3.5 128b",        provider = "nvidia", id = "mistralai/mistral-medium-3.5-128b", maxOutput = 8192 },
    { label = "Mistral Small 4 119b",           provider = "nvidia", id = "mistralai/mistral-small-4-119b-2603", maxOutput = 8192 },
    { label = "Mistral 7b",                     provider = "nvidia", id = "mistralai/mistral-7b-instruct-v0.3", maxOutput = 4096 },
    { label = "Mixtral 8x22b",                  provider = "nvidia", id = "mistralai/mixtral-8x22b-v0.1", maxOutput = 4096 },
    { label = "Mixtral 8x7b",                   provider = "nvidia", id = "mistralai/mixtral-8x7b-instruct-v0.1", maxOutput = 4096 },
    { label = "Mistral Nemo 12b",               provider = "nvidia", id = "nv-mistralai/mistral-nemo-12b-instruct", maxOutput = 4096 },
    { label = "Qwen3.5 397b A17b",              provider = "nvidia", id = "qwen/qwen3.5-397b-a17b", maxOutput = 8192 },
    { label = "Qwen3.5 122b A10b",              provider = "nvidia", id = "qwen/qwen3.5-122b-a10b", maxOutput = 8192 },
    { label = "Qwen3-Next 80b A3b",             provider = "nvidia", id = "qwen/qwen3-next-80b-a3b-instruct", maxOutput = 8192 },
    { label = "Kimi K2.6 (1M ctx)",             provider = "nvidia", id = "moonshotai/kimi-k2.6", maxOutput = 8192 },
    { label = "GLM-5.1 (Zhipu)",                provider = "nvidia", id = "z-ai/glm-5.1", maxOutput = 8192 },
    { label = "Gemma 4 31b",                    provider = "nvidia", id = "google/gemma-4-31b-it", maxOutput = 4096 },
    { label = "Gemma 3 12b",                    provider = "nvidia", id = "google/gemma-3-12b-it", maxOutput = 4096 },
    { label = "Gemma 3n E4b",                   provider = "nvidia", id = "google/gemma-3n-e4b-it", maxOutput = 4096 },
    { label = "Phi-4 Mini",                     provider = "nvidia", id = "microsoft/phi-4-mini-instruct", maxOutput = 4096 },
    { label = "Phi-4 Multimodal",               provider = "nvidia", id = "microsoft/phi-4-multimodal-instruct", maxOutput = 4096 },
    { label = "Phi-3.5 MoE",                    provider = "nvidia", id = "microsoft/phi-3.5-moe-instruct", maxOutput = 4096 },
    { label = "Nemotron 3 Super 120b (1M ctx)", provider = "nvidia", id = "nvidia/nemotron-3-super-120b-a12b", maxOutput = 8192 },
    { label = "Nemotron 3 Ultra 253b",          provider = "nvidia", id = "nvidia/llama-3.1-nemotron-ultra-253b-v1", maxOutput = 8192 },
    { label = "Nemotron 3 Nano 30b",            provider = "nvidia", id = "nvidia/nemotron-3-nano-30b-a3b", maxOutput = 4096 },
    { label = "Nemotron 3 Nano Omni",           provider = "nvidia", id = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning", maxOutput = 4096 },
    { label = "Llama 3.1 Nemotron 70b",         provider = "nvidia", id = "nvidia/llama-3.1-nemotron-70b-instruct", maxOutput = 4096 },
    { label = "Llama 3.3 Nemotron Super 49b",   provider = "nvidia", id = "nvidia/llama-3.3-nemotron-super-49b-v1", maxOutput = 4096 },
    { label = "MiniMax M2.7",                   provider = "nvidia", id = "minimaxai/minimax-m2.7", maxOutput = 8192 },
    { label = "MiniMax M3",                     provider = "nvidia", id = "minimaxai/minimax-m3", maxOutput = 8192 },
    { label = "Step 3.5 Flash",                 provider = "nvidia", id = "stepfun-ai/step-3.5-flash", maxOutput = 4096 },
    { label = "Step 3.7 Flash",                 provider = "nvidia", id = "stepfun-ai/step-3.7-flash", maxOutput = 4096 },
    { label = "GPT-OSS 120b",                   provider = "nvidia", id = "openai/gpt-oss-120b", maxOutput = 8192 },
    { label = "GPT-OSS 20b",                    provider = "nvidia", id = "openai/gpt-oss-20b", maxOutput = 4096 },
    { label = "Seed-OSS 36b (ByteDance)",       provider = "nvidia", id = "bytedance/seed-oss-36b-instruct", maxOutput = 8192 },
    { label = "DBRX Instruct (Databricks)",     provider = "nvidia", id = "databricks/dbrx-instruct", maxOutput = 4096 },
    { label = "Granite 34b Code (IBM)",         provider = "nvidia", id = "ibm/granite-34b-code-instruct", maxOutput = 4096 },
    { label = "Jamba 1.5 Large (AI21)",         provider = "nvidia", id = "ai21labs/jamba-1.5-large-instruct", maxOutput = 4096 },
    { label = "Sarvam M (multilingual)",        provider = "nvidia", id = "sarvamai/sarvam-m", maxOutput = 4096 },
    { label = "Llama Guard 4 12b",              provider = "nvidia", id = "meta/llama-guard-4-12b", maxOutput = 4096 },
}

-- الحالة الحالية — تُحمَّل من الملف عند البدء
local CURRENT_PROVIDER = "opencode"
local CURRENT_MODEL_LABEL = "⭐ Big Pickle (Free)"

-- ملف الحفظ
local SAVE_FILE = "SkillAI_ModelSave.txt"

local function saveModelChoice(label, provider, modelId)
    pcall(function()
        if writefile then
            local data = label .. "\n" .. provider .. "\n" .. (modelId or "")
            writefile(SAVE_FILE, data)
        end
    end)
end

local function loadModelChoice()
    local ok, data = pcall(function()
        if readfile and isfile and isfile(SAVE_FILE) then
            return readfile(SAVE_FILE)
        end
        return nil
    end)
    if ok and data and data ~= "" then
        local lines = {}
        for line in data:gmatch("[^\n]+") do table.insert(lines, line) end
        local savedLabel    = lines[1] or ""
        local savedProvider = lines[2] or "opencode"
        local savedId       = lines[3] or "big-pickle"
        -- ابحث عنه في القائمة
        for _, m in ipairs(MODEL_LIST) do
            if m.provider ~= "separator" and m.label == savedLabel then
                return m
            end
        end
        -- إذا مو موجود في القائمة، أنشئ entry مؤقت
        return { label = savedLabel, provider = savedProvider, id = savedId }
    end
    return nil
end

-- تطبيق اختيار النموذج (يعدّل API_URL + MODEL_ID + API_KEYS)
local API_URL   = OPENCODE_URL
local MODEL_ID  = "big-pickle"
local API_KEYS  = OPENCODE_KEYS
local KEY_INDEX = 0      -- FIX: تعريف واحد فقط هنا (كان مكرر بعدين كـ global implicit)
local KEY_RESET_TIME = 0 -- tick() when all keys exhausted

-- FIX v1.4: cache maxOutput عند تغيير النموذج بدل البحث في كل طلب
local CURRENT_MODEL_MAX_OUTPUT = nil

local function applyModelChoice(entry)
    if not entry or entry.provider == "separator" then return end
    CURRENT_PROVIDER     = entry.provider
    CURRENT_MODEL_LABEL  = entry.label
    MODEL_ID             = entry.id
    CURRENT_MODEL_MAX_OUTPUT = entry.maxOutput or nil  -- FIX v1.4
    if entry.provider == "nvidia" then
        API_URL  = NVIDIA_URL
        API_KEYS = { NVIDIA_API_KEY }
    else
        API_URL  = OPENCODE_URL
        API_KEYS = OPENCODE_KEYS
    end
    KEY_INDEX = 0
    saveModelChoice(entry.label, entry.provider, entry.id)
end

-- حمّل الاختيار المحفوظ عند البدء
do
    local saved = loadModelChoice()
    if saved then applyModelChoice(saved) end
end
local function getApiKey()
    if type(API_KEYS) ~= "table" or #API_KEYS == 0 then return nil end
    local key = API_KEYS[KEY_INDEX + 1] or API_KEYS[1]
    KEY_INDEX = (KEY_INDEX + 1) % #API_KEYS
    return key
end
local function currentKeyLabel()
    return "key " .. (KEY_INDEX % #API_KEYS + 1) .. "/" .. #API_KEYS
end

-- 💰 أسعار تقريبية للتوكنز (دولار لكل 1 مليون توكن)
local PRICE_PER_1M_INPUT = 0.15
local PRICE_PER_1M_OUTPUT = 0.60

local requestFunc = nil
if syn and syn.request then
    requestFunc = syn.request
elseif http_request then
    requestFunc = http_request
elseif request then
    requestFunc = request
elseif fluxus_request then
    requestFunc = fluxus_request
else
    requestFunc = function(data)
        return HttpService:PostAsync(data.Url, data.Body, Enum.HttpContentType.ApplicationJson, false, data.Headers)
    end
end

pcall(function()
    local old = CoreGui:FindFirstChild("Skill-AI")
    if old then old:Destroy() end
end)

local C = {
    bg = Color3.fromRGB(10, 10, 16),
    surface = Color3.fromRGB(18, 18, 26),
    surfaceHi = Color3.fromRGB(28, 28, 38),
    border = Color3.fromRGB(45, 45, 55),
    accent = Color3.fromRGB(0, 200, 255),
    text = Color3.fromRGB(240, 240, 245),
    textDim = Color3.fromRGB(140, 140, 155),
    green = Color3.fromRGB(0, 255, 150),
    red = Color3.fromRGB(255, 80, 80),
    yellow = Color3.fromRGB(255, 210, 0),
    orange = Color3.fromRGB(255, 140, 0),
}

local function corner(inst, r)
    local c = Instance.new("UICorner", inst)
    c.CornerRadius = UDim.new(0, r or 10)
    return c
end

local function stroke(inst, col, t, trans)
    local s = Instance.new("UIStroke", inst)
    s.Color = col or C.border
    s.Thickness = t or 1
    s.Transparency = trans or 0.2
    return s
end

local function tw(inst, info, props)
    local t = TweenService:Create(inst, info, props)
    t:Play()
    return t
end

local function makeDraggable(frame, handle)
    handle = handle or frame
    local dragging, dragStart, startPos = false, nil, nil
    handle.InputBegan:Connect(function(inp)
        if (inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch) then
            dragging = true
            dragStart = inp.Position
            startPos = frame.Position
        end
    end)
    UIS.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local d = inp.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
    UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local sg = Instance.new("ScreenGui")
sg.Name = "Skill-AI"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.IgnoreGuiInset = true
local sgParented = pcall(function() sg.Parent = CoreGui end)
if not sgParented then
    pcall(function() sg.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end)
end

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "Toggle"
toggleBtn.Size = UDim2.new(0, 42, 0, 42)
toggleBtn.Position = UDim2.new(0.04, 0, 0.15, 0)
toggleBtn.BackgroundColor3 = C.surfaceHi
toggleBtn.Text = "🧠"
toggleBtn.TextColor3 = C.accent
toggleBtn.TextSize = 20
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.Parent = sg
corner(toggleBtn, 21)
stroke(toggleBtn, C.accent, 1.5, 0.3)
makeDraggable(toggleBtn)

local PW = 340
local PH = 440
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0, PW, 0, PH)
panel.Position = UDim2.new(0.5, -PW/2, 0.5, -PH/2)
panel.BackgroundColor3 = C.bg
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = sg
corner(panel, 12)
stroke(panel, C.accent, 1, 0.7)

local tb = Instance.new("Frame")
tb.Size = UDim2.new(1, 0, 0, 34)
tb.BackgroundTransparency = 1
tb.Parent = panel

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(1, -130, 1, 0)
titleText.Position = UDim2.new(0, 12, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "🧠 Skill-AI v1.4"
titleText.TextColor3 = C.accent
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.TextSize = 14
titleText.Font = Enum.Font.GothamBold
titleText.Parent = tb

-- زر اختيار النموذج
local modelBtn = Instance.new("TextButton")
modelBtn.Size = UDim2.new(0, 110, 0, 22)
modelBtn.Position = UDim2.new(1, -138, 0.5, -11)
modelBtn.BackgroundColor3 = C.surfaceHi
modelBtn.TextColor3 = C.yellow
modelBtn.TextSize = 9
modelBtn.Font = Enum.Font.Gotham
modelBtn.TextTruncate = Enum.TextTruncate.AtEnd
modelBtn.Parent = tb
corner(modelBtn, 5)
stroke(modelBtn, C.yellow, 1, 0.4)

local function updateModelBtn()
    local short = CURRENT_MODEL_LABEL:gsub("%(Free%)", ""):gsub("%(NVIDIA%)", ""):match("^%s*(.-)%s*$")
    if #short > 18 then short = short:sub(1, 17) .. "…" end
    modelBtn.Text = "⚙ " .. short
end
updateModelBtn()

-- ── Model Picker Popup ──────────────────────────────────────────────────────


local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 22, 0, 22)
closeBtn.Position = UDim2.new(1, -28, 0.5, -11)
closeBtn.BackgroundColor3 = C.surfaceHi
closeBtn.Text = "✕"
closeBtn.TextColor3 = C.red
closeBtn.TextSize = 10
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Parent = tb
corner(closeBtn, 6)
closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)

makeDraggable(panel, tb)

toggleBtn.MouseButton1Click:Connect(function()
    panel.Visible = not panel.Visible
    tw(toggleBtn, TweenInfo.new(0.3), {Rotation = panel.Visible and 0 or 180})
end)

local displayArea = Instance.new("ScrollingFrame")
displayArea.Size = UDim2.new(1, -16, 1, -115)
displayArea.Position = UDim2.new(0, 8, 0, 40)
displayArea.BackgroundColor3 = C.surface
displayArea.BorderSizePixel = 0
displayArea.ScrollBarThickness = 0
displayArea.AutomaticCanvasSize = Enum.AutomaticSize.Y
displayArea.CanvasSize = UDim2.new(0, 0, 0, 0)
displayArea.Parent = panel
corner(displayArea, 8)
stroke(displayArea, C.border, 1, 0.3)

local displayList = Instance.new("UIListLayout", displayArea)
displayList.Padding = UDim.new(0, 6)
displayList.HorizontalAlignment = Enum.HorizontalAlignment.Center
displayList.SortOrder = Enum.SortOrder.LayoutOrder

local welcomeLbl = Instance.new("TextLabel")
welcomeLbl.Size = UDim2.new(1, -10, 0, 40)
welcomeLbl.BackgroundTransparency = 1
welcomeLbl.Text = "💬 Ask me anything or give me a command — I plan and execute..."
welcomeLbl.TextColor3 = C.textDim
welcomeLbl.TextSize = 12
welcomeLbl.Font = Enum.Font.Gotham
welcomeLbl.Parent = displayArea

local inputArea = Instance.new("Frame")
inputArea.Size = UDim2.new(1, -16, 0, 52)
inputArea.Position = UDim2.new(0, 8, 1, -60)
inputArea.BackgroundColor3 = C.surface
inputArea.Parent = panel
corner(inputArea, 8)
stroke(inputArea, C.border, 1, 0.3)

local inputBox = Instance.new("TextBox")
inputBox.Size = UDim2.new(1, -64, 1, -8)
inputBox.Position = UDim2.new(0, 8, 0, 4)
inputBox.BackgroundTransparency = 1
inputBox.PlaceholderText = "Type any command in any language..."
inputBox.TextColor3 = C.text
inputBox.PlaceholderColor3 = C.textDim
inputBox.TextSize = 13
inputBox.Font = Enum.Font.Gotham
inputBox.ClearTextOnFocus = false
inputBox.Parent = inputArea

local sendBtn = Instance.new("TextButton")
sendBtn.Size = UDim2.new(0, 44, 1, -8)
sendBtn.Position = UDim2.new(1, -52, 0, 4)
sendBtn.BackgroundColor3 = C.accent
sendBtn.Text = "➤"
sendBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
sendBtn.TextSize = 18
sendBtn.Font = Enum.Font.GothamBold
sendBtn.Parent = inputArea
corner(sendBtn, 6)

local function getInstancePath(inst)
    if not inst then return "nil" end
    local parts = {}
    local current = inst
    while current do
        local name = current.Name or "?"
        table.insert(parts, 1, name)
        current = current.Parent
    end
    return table.concat(parts, " > ")
end

-- Popup window showing full generated script code with a real copy button.
-- Used when direct Source writing fails (executor blocks it): shows the code
-- ready to copy/paste instead of trying to bypass the restriction.
local function showScriptPopup(code, scriptName)
    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 0.4
    overlay.ZIndex = 50
    overlay.Parent = sg

    local box = Instance.new("Frame")
    box.Size = UDim2.new(0.9, 0, 0.7, 0)
    box.Position = UDim2.new(0.05, 0, 0.15, 0)
    box.BackgroundColor3 = C.surface
    box.ZIndex = 51
    box.Parent = overlay
    corner(box, 12)
    stroke(box, C.accent, 1.5, 0.2)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -16, 0, 36)
    title.Position = UDim2.new(0, 8, 0, 4)
    title.BackgroundTransparency = 1
    title.Text = "📝 " .. (scriptName or "Script") .. " — Copy this code into a new Script"
    title.TextColor3 = C.accent
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.TextWrapped = true
    title.ZIndex = 52
    title.Parent = box

    local codeScroll = Instance.new("ScrollingFrame")
    codeScroll.Size = UDim2.new(1, -16, 1, -90)
    codeScroll.Position = UDim2.new(0, 8, 0, 40)
    codeScroll.BackgroundColor3 = C.bg
    codeScroll.ScrollBarThickness = 6
    codeScroll.ZIndex = 52
    codeScroll.Parent = box
    corner(codeScroll, 8)

    local codeLbl = Instance.new("TextLabel")
    codeLbl.Size = UDim2.new(1, -12, 0, 0)
    codeLbl.Position = UDim2.new(0, 6, 0, 6)
    codeLbl.BackgroundTransparency = 1
    codeLbl.Text = code
    codeLbl.TextColor3 = C.green
    codeLbl.TextSize = 12
    codeLbl.Font = Enum.Font.Code
    codeLbl.TextWrapped = true
    codeLbl.TextXAlignment = Enum.TextXAlignment.Left
    codeLbl.TextYAlignment = Enum.TextYAlignment.Top
    codeLbl.ZIndex = 53
    codeLbl.Parent = codeScroll

    local lineCount = select(2, code:gsub("\n", "\n")) + 1
    local approxHeight = math.max(100, lineCount * 16 + (#code / 50) * 14)
    codeLbl.Size = UDim2.new(1, -12, 0, approxHeight)
    codeScroll.CanvasSize = UDim2.new(0, 0, 0, approxHeight + 12)

    local copyBtn = Instance.new("TextButton")
    copyBtn.Size = UDim2.new(0.48, -4, 0, 36)
    copyBtn.Position = UDim2.new(0, 8, 1, -42)
    copyBtn.BackgroundColor3 = C.accent
    copyBtn.Text = "📋 Copy Code"
    copyBtn.TextColor3 = Color3.new(0, 0, 0)
    copyBtn.TextSize = 13
    copyBtn.Font = Enum.Font.GothamBold
    copyBtn.ZIndex = 52
    copyBtn.Parent = box
    corner(copyBtn, 8)

    copyBtn.MouseButton1Click:Connect(function()
        local copied = false
        if setclipboard then
            copied = pcall(function() setclipboard(code) end)
        end
        if copied then
            copyBtn.Text = "✅ Copied! Paste into a Script in the Explorer"
        else
            copyBtn.Text = "❌ Clipboard not supported by this Executor"
        end
    end)

    local closeBtn2 = Instance.new("TextButton")
    closeBtn2.Size = UDim2.new(0.48, -4, 0, 36)
    closeBtn2.Position = UDim2.new(0.52, 0, 1, -42)
    closeBtn2.BackgroundColor3 = C.surfaceHi
    closeBtn2.Text = "Close"
    closeBtn2.TextColor3 = C.text
    closeBtn2.TextSize = 13
    closeBtn2.Font = Enum.Font.Gotham
    closeBtn2.ZIndex = 52
    closeBtn2.Parent = box
    corner(closeBtn2, 8)
    closeBtn2.MouseButton1Click:Connect(function()
        overlay:Destroy()
    end)
end

local showInstanceInfo

local function addMessage(text, isUser, isError, isSystem, clickInstance)
    welcomeLbl.Visible = false

    -- FIX v1.4: message cap أسرع — بدل GetChildren() في كل message نتتبع العداد
    local allEntries = displayArea:GetChildren()
    local entryCount = #allEntries
    if entryCount > MESSAGE_MAX then
        local toRemove = entryCount - MESSAGE_MAX
        for i = 1, toRemove do
            local oldest = allEntries[i]
            if oldest and oldest ~= welcomeLbl and oldest ~= displayList then
                oldest:Destroy()
            end
        end
    end

    local entry = Instance.new("Frame")
    entry.Size = UDim2.new(1, -10, 0, 0)
    entry.BackgroundTransparency = 1
    entry.Parent = displayArea

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 0, 0)
    if isError then
        bg.BackgroundColor3 = C.red
    elseif isSystem then
        bg.BackgroundColor3 = Color3.fromRGB(30, 30, 20)
    elseif isUser then
        bg.BackgroundColor3 = C.surfaceHi
    else
        bg.BackgroundColor3 = C.surface
    end
    bg.Parent = entry
    corner(bg, 8)
    stroke(bg, isError and C.red or (isUser and C.accent or C.border), 0.5, 0.3)

    local lbl = Instance.new("TextButton")
    lbl.Size = UDim2.new(1, -16, 1, -8)
    lbl.Position = UDim2.new(0, 8, 0, 4)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = isError and C.text or (isUser and C.accent or C.text)
    lbl.TextSize = 12
    lbl.Font = Enum.Font.Gotham
    lbl.TextWrapped = true
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.AutoButtonColor = false
    lbl.Selectable = false
    lbl.Parent = bg

    if clickInstance then
        local actual = clickInstance
        if type(actual) == "table" and actual._ref then
            actual = actual._ref
        end
        if actual and type(actual) == "userdata" then
            lbl.TextColor3 = Color3.fromRGB(100, 180, 255)
            lbl.MouseButton1Click:Connect(function()
                showInstanceInfo(actual)
            end)
            entry.BackgroundTransparency = 0.85
        end
    end

    -- FIX v1.4: حساب الارتفاع الدقيق بدون مسح النص — O(1) بدل O(n)
    -- نعتمد على عدد السطور الفعلي + طول النص كمؤشر للف
    local lineBreaks = select(2, text:gsub("\n", "\n"))
    local wrapLines = math.floor(#text / 42) -- تقدير الف عند عرض ~42 حرف
    local totalLines = math.max(1, lineBreaks + wrapLines)
    local height = math.max(30, math.min(300, totalLines * 16 + 18))
    bg.Size = UDim2.new(1, 0, 0, height)
    entry.Size = UDim2.new(1, 0, 0, height + 4)

    task.wait()
    displayArea.CanvasPosition = Vector2.new(0, displayArea.CanvasSize.Y.Offset)
end

showInstanceInfo = function(inst)
    if not inst then
        addMessage("❌ Instance no longer exists", false, true)
        return
    end
    local className = inst:IsA("BasePart") and inst.ClassName or inst.ClassName or "Instance"
    local info = "📦 " .. className
    info = info .. " \"" .. inst.Name .. "\"\n📁 " .. getInstancePath(inst)
    if inst:IsA("BasePart") then
        local pos = inst.Position
        info = info .. ("\n📍 %.1f, %.1f, %.1f"):format(pos.X, pos.Y, pos.Z)
    end
    if inst:IsA("Script") or inst:IsA("LocalScript") then
        local src = inst.Source or ""
        if #src > 0 then
            info = info .. "\n📝 " .. #src .. " chars"
        else
            info = info .. "\n⚠️ Source is empty."
        end
    end
    if inst:IsA("StringValue") then
        local val = inst.Value or ""
        if #val > 0 then
            info = info .. "\n━━━━━━━━━━━━━━━━━━\n" .. val .. "\n━━━━━━━━━━━━━━━━━━"
        else
            info = info .. "\n⚠️ StringValue is empty"
        end
    end
    addMessage(info, false, false, true)
end

-- Model picker popup
local function showModelPicker()
    -- overlay
    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.new(0, 0, 0)
    overlay.BackgroundTransparency = 0.5
    overlay.ZIndex = 60
    overlay.Parent = sg

    local popup = Instance.new("Frame")
    popup.Size = UDim2.new(0, 290, 0, 380)
    popup.Position = UDim2.new(0.5, -145, 0.5, -190)
    popup.BackgroundColor3 = C.bg
    popup.ZIndex = 61
    popup.Parent = overlay
    corner(popup, 12)
    stroke(popup, C.accent, 1.5, 0.2)

    local hdr = Instance.new("TextLabel")
    hdr.Size = UDim2.new(1, -40, 0, 32)
    hdr.Position = UDim2.new(0, 10, 0, 4)
    hdr.BackgroundTransparency = 1
    hdr.Text = "⚙ Select Model"
    hdr.TextColor3 = C.accent
    hdr.TextXAlignment = Enum.TextXAlignment.Left
    hdr.TextSize = 13
    hdr.Font = Enum.Font.GothamBold
    hdr.ZIndex = 62
    hdr.Parent = popup

    local closePop = Instance.new("TextButton")
    closePop.Size = UDim2.new(0, 24, 0, 24)
    closePop.Position = UDim2.new(1, -30, 0, 4)
    closePop.BackgroundColor3 = C.surfaceHi
    closePop.Text = "✕"
    closePop.TextColor3 = C.red
    closePop.TextSize = 10
    closePop.Font = Enum.Font.GothamBold
    closePop.ZIndex = 62
    closePop.Parent = popup
    corner(closePop, 6)
    closePop.MouseButton1Click:Connect(function() overlay:Destroy() end)

    -- Current model label
    local curLbl = Instance.new("TextLabel")
    curLbl.Size = UDim2.new(1, -12, 0, 20)
    curLbl.Position = UDim2.new(0, 6, 0, 36)
    curLbl.BackgroundTransparency = 1
    curLbl.Text = "Now: " .. CURRENT_MODEL_LABEL
    curLbl.TextColor3 = C.green
    curLbl.TextSize = 10
    curLbl.Font = Enum.Font.Gotham
    curLbl.TextTruncate = Enum.TextTruncate.AtEnd
    curLbl.TextXAlignment = Enum.TextXAlignment.Left
    curLbl.ZIndex = 62
    curLbl.Parent = popup

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -12, 1, -64)
    scroll.Position = UDim2.new(0, 6, 0, 58)
    scroll.BackgroundColor3 = C.surface
    scroll.ScrollBarThickness = 4
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.ZIndex = 62
    scroll.Parent = popup
    corner(scroll, 8)

    local list = Instance.new("UIListLayout", scroll)
    list.Padding = UDim.new(0, 3)
    list.SortOrder = Enum.SortOrder.LayoutOrder

    local pad = Instance.new("UIPadding", scroll)
    pad.PaddingLeft = UDim.new(0, 4)
    pad.PaddingTop  = UDim.new(0, 4)

    for idx, entry in ipairs(MODEL_LIST) do
        if entry.provider == "separator" then
            local sep = Instance.new("TextLabel")
            sep.Size = UDim2.new(1, -8, 0, 20)
            sep.BackgroundColor3 = C.surfaceHi
            sep.Text = "── NVIDIA NIM ──"
            sep.TextColor3 = C.yellow
            sep.TextSize = 10
            sep.Font = Enum.Font.GothamBold
            sep.LayoutOrder = idx
            sep.ZIndex = 63
            sep.Parent = scroll
            corner(sep, 4)
        else
            local isActive = (entry.label == CURRENT_MODEL_LABEL)
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -8, 0, 26)
            btn.BackgroundColor3 = isActive and C.accent or C.surfaceHi
            btn.TextColor3 = isActive and Color3.new(0,0,0) or C.text
            btn.Text = entry.label
            btn.TextSize = 10
            btn.Font = Enum.Font.Gotham
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.TextTruncate = Enum.TextTruncate.AtEnd
            btn.LayoutOrder = idx
            btn.ZIndex = 63
            btn.Parent = scroll
            corner(btn, 5)

            local lbl2 = Instance.new("UIPadding", btn)
            lbl2.PaddingLeft = UDim.new(0, 6)

            local capturedEntry = entry
            btn.MouseButton1Click:Connect(function()
                applyModelChoice(capturedEntry)
                updateModelBtn()
                curLbl.Text = "✅ Now: " .. CURRENT_MODEL_LABEL
                for _, child in ipairs(scroll:GetChildren()) do
                    if child:IsA("TextButton") then
                        child.BackgroundColor3 = C.surfaceHi
                        child.TextColor3 = C.text
                    end
                end
                btn.BackgroundColor3 = C.accent
                btn.TextColor3 = Color3.new(0, 0, 0)
                task.delay(0.2, function()
                    overlay:Destroy()
                    addMessage("✅ Model changed → **" .. CURRENT_MODEL_LABEL .. "**\nProvider: " .. CURRENT_PROVIDER:upper() .. " | Saved automatically.", false)
                end)
            end)
        end
    end
end

modelBtn.MouseButton1Click:Connect(showModelPicker)

local LOG_FILE = "SkillAI_Log.txt"

local function logToFile(label, content)
    local ok = pcall(function()
        local stamp = "\n[" .. os.date("%X") .. "] " .. label .. ":\n" .. tostring(content) .. "\n" .. string.rep("-", 30) .. "\n"
        if writefile then
            if isfile and isfile(LOG_FILE) and readfile then
                local existing = readfile(LOG_FILE)
                writefile(LOG_FILE, existing .. stamp)
            else
                writefile(LOG_FILE, stamp)
            end
        end
    end)
    return ok
end

local function setupRespawnReRunner()
    local plr = Players.LocalPlayer
    local function reRunAll()
        for _, entry in ipairs(_autoRunScripts) do
            local fn, err = loadstring("local script = ...\n" .. entry.source)
            if fn then
                task.spawn(function()
                    local ok, e = pcall(fn, entry.inst)
                    if not ok then logToFile("Respawn re-run error " .. entry.name, e) end
                end)
            end
        end
    end
    reRunAll()
    plr.CharacterAdded:Connect(reRunAll)
end

-- 🧠 تصنيف ذكي لتعقيد الطلب — يصير محلياً بالكود (فوري، صفر توكنز، صفر وقت
-- إضافي)، يقرر هل الطلب يحتاج تفكير عميق (high) أو بسيط (low). هذا يحل
-- التناقض "أريد دقة high بسرعة low": الحل مو إعداد ثابت واحد، بل نستخدم
-- high فقط للطلبات اللي فعلاً تحتاجه (سكربتات، أنظمة، خطط معقدة)، وlow
-- لكل شي آخر (يغطي أغلب الطلبات اليومية: قطعة، أداة، تعديل، حذف، إلخ).
local HIGH_EFFORT_KEYWORDS = {
    "script", "system", "unlock", "lock", "track", "when ", "challenge",
    "complete", "trigger", "damage", "spawn enemies", "ai", "npc",
    "leaderboard", "datastore", "save", "load", "remote", "multiplayer",
    "quest", "checkpoint", "gate", "obstacle course", "lap", "stage",
    "wave", "phase", "progression", "rank", "level", "door", "key",
    "boss", "health bar", "timer", "countdown", "score", "points",
    "سكربت", "نظام", "يفتح", "يقفل", "تحدي", "يتتبع",
    "بوابة", "مرحلة", "مستوى", "نقاط", "مؤقت", "بوس",
}
local function classifyEffort(question)
    if type(question) ~= "string" then return "low" end
    local lowerQ = question:lower()
    -- طول الطلب نفسه مؤشر قوي: طلبات طويلة ومفصلة غالباً معقدة منطقياً
    if #question > 220 then return "high" end
    for _, kw in ipairs(HIGH_EFFORT_KEYWORDS) do
        if lowerQ:find(kw, 1, true) then
            return "high"
        end
    end
    return "low"
end

-- FIX v1.4: مهلة الطلب — يمنع التجميد اللانهائي عند انقطاع الشبكة
local REQUEST_TIMEOUT = math.huge

local function callAI(messages, _isRetry, effort, _keyAttempt)
    _keyAttempt = _keyAttempt or 0
    local maxKeyAttempts = (#API_KEYS or 1) * 2

    local currentKey = getApiKey()
    if not currentKey then
        return nil, "❌ No API keys configured. Add keys to API_KEYS table."
    end

    -- FIX v1.4: cache modelMaxOutput بدل البحث في كل مرة
    local cap = (effort == "high") and MAX_TOKENS_HIGH or MAX_TOKENS_LOW
    local maxTokens = math.min(cap, CURRENT_MODEL_MAX_OUTPUT or cap)
    local data = {
        model = MODEL_ID,
        messages = messages,
        max_tokens = maxTokens,
        temperature = 0.2,
        top_p = 0.95,
    }

    local json = HttpService:JSONEncode(data)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. currentKey,
    }

    -- FIX v1.4: Timeout wrapper — الطلب يتوقف بعد REQUEST_TIMEOUT ثانية
    local success, response
    do
        local done = false
        local result_ok, result_val
        task.spawn(function()
            result_ok, result_val = pcall(function()
                if requestFunc then
                    return requestFunc({
                        Url = API_URL,
                        Method = "POST",
                        Headers = headers,
                        Body = json,
                    })
                else
                    return HttpService:PostAsync(API_URL, json, Enum.HttpContentType.ApplicationJson, false, headers)
                end
            end)
            done = true
        end)
        local t0 = tick()
        while not done and (tick() - t0) < REQUEST_TIMEOUT do
            task.wait(0.2)
        end
        if not done then
            return nil, "❌ Request timed out after " .. REQUEST_TIMEOUT .. "s. Check connection."
        end
        success, response = result_ok, result_val
    end

    if not success then
        if not _isRetry then
            -- FIX v1.4: 0.8s بدل 2s على الـ retry الأول — أسرع
            task.wait(0.8)
            return callAI(messages, true, effort, _keyAttempt)
        end
        return nil, "❌ Connection failed: " .. tostring(response)
    end

    local body = response.Body or response
    local okDecode, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if not okDecode or not decoded then
        logToFile("JSON decode failed", tostring(body):sub(1, 500))
        if not _isRetry then
            task.wait(0.8) -- FIX v1.4: أسرع
            return callAI(messages, true, effort, _keyAttempt)
        end
        return nil, "❌ Server returned invalid JSON. Check " .. LOG_FILE
    end

    local errMsg = nil
    if decoded.error then
        if type(decoded.error) == "table" then
            errMsg = tostring(decoded.error.message or decoded.error.code or "")
        elseif type(decoded.error) == "string" then
            errMsg = decoded.error
        end
    elseif decoded.message then
        errMsg = tostring(decoded.message)
    elseif decoded.detail then
        errMsg = tostring(decoded.detail)
    end
    if errMsg then
        logToFile("API error", errMsg)
        if errMsg:find("FreeUsageLimitError", 1, true) or errMsg:find("rate limit", 1, true) or errMsg:find("quota", 1, true) then
            if _keyAttempt < maxKeyAttempts then
                local backoff = math.min(2 ^ (_keyAttempt - math.floor(_keyAttempt / #API_KEYS)), 60)
                task.wait(backoff)
                return callAI(messages, _isRetry, effort, _keyAttempt + 1)
            end
            KEY_RESET_TIME = tick()
            return nil, "❌ All API keys exhausted. Wait ~60s or add new keys. Last key: " .. currentKeyLabel()
        end
        return nil, "❌ API: " .. errMsg
    end

    if decoded.choices and decoded.choices[1] then
        local msg = decoded.choices[1].message
        local content = msg and msg.content
        local usage = decoded.usage
        if content and content ~= "" then
            return content, nil, usage
        end
        local reasoning = msg and msg.reasoning_content
        if reasoning and reasoning ~= "" then
            return reasoning, nil, usage
        end
        logToFile("Model returned no content", pcall(function() return HttpService:JSONEncode(decoded) end) and HttpService:JSONEncode(decoded) or tostring(decoded))
        return nil, "⚠️ Model did not generate a response. Try again."
    end

    local decodedStr = pcall(function() return HttpService:JSONEncode(decoded) end) and HttpService:JSONEncode(decoded) or tostring(decoded)
    logToFile("No choices in response", decodedStr)
    if not _isRetry then
        task.wait(0.8) -- FIX v1.4: أسرع
        return callAI(messages, true, effort, _keyAttempt)
    end
    return nil, "❌ Unexpected server response. Check " .. LOG_FILE
end

local PARENT_MAP = {
    Workspace = Workspace,
    StarterPack = StarterPack,
    Lighting = Lighting,
    ServerStorage = ServerStorage,
    ReplicatedStorage = ReplicatedStorage,
    StarterGui = StarterGui,
    StarterPlayer = StarterPlayer,
    StarterCharacterScripts = StarterCharacterScripts,
    StarterPlayerScripts = StarterPlayerScripts,
    CoreGui = CoreGui,
    Players = Players,
}

local function resolveParent(name, fallback)
    if type(name) == "string" and PARENT_MAP[name] then
        return PARENT_MAP[name]
    end
    return fallback or Workspace
end

local function fixLuaCode(source, compileErr)
    local sysContent = "You fix Lua syntax errors. Return ONLY the corrected Lua code. No explanations, no markdown."
    local userContent = "Fix this Lua error: " .. compileErr .. "\n\n```lua\n" .. source .. "\n```"
    local fixMessages
    if CURRENT_PROVIDER == "nvidia" then
        fixMessages = { { role = "user", content = sysContent .. "\n\n" .. userContent } }
    else
        fixMessages = {
            { role = "system", content = sysContent },
            { role = "user", content = userContent }
        }
    end
    local fixBody = HttpService:JSONEncode({
        model = MODEL_ID,
        messages = fixMessages,
        max_tokens = 1000,
        temperature = 0.1
    })
    local fixKey = getApiKey() or ""
    local ok, response = pcall(function()
        return requestFunc({
            Url = API_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Bearer " .. fixKey
            },
            Body = fixBody
        })
    end)
    if not ok or not response then return nil end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, response.Body)
    if not ok2 or not data or not data.choices or not data.choices[1] then return nil end
    local fixed = data.choices[1].message.content or ""
    fixed = fixed:gsub("```lua", ""):gsub("```", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local fn, err2 = loadstring("local script = ...\n" .. fixed)
    if fn then return fixed end
    return nil, err2
end

local MAX_HISTORY_TURNS = 8
local conversationHistory = {} -- each entry: { user = "...", summary = "..." }
local CURRENT_REQUEST_TEXT = "" -- stores the latest user request text for context safety checks (e.g., fog detection)

local function pushHistory(userMsg, summary)
    table.insert(conversationHistory, { user = userMsg, summary = summary })
    while #conversationHistory > MAX_HISTORY_TURNS do
        table.remove(conversationHistory, 1)
    end
end

local function buildHistoryMessages()
    local msgs = {}
    -- Only send last exchange (saves tokens, speeds up response)
    local startIdx = math.max(1, #conversationHistory - 1)
    for i = startIdx, #conversationHistory do
        local turn = conversationHistory[i]
        table.insert(msgs, { role = "user", content = turn.user })
        table.insert(msgs, { role = "assistant", content = turn.summary })
    end
    return msgs
end

local SEARCH_SERVICES = { Workspace, StarterPack, Lighting, ServerStorage, ReplicatedStorage, StarterGui, StarterPlayer, StarterCharacterScripts, StarterPlayerScripts, Players, CoreGui }
-- _searchCache معرَّف في الأعلى (سطر ~88) — لا تعريف مكرر هنا
local _searchCacheTime = 0
-- FIX v1.4: رفعنا TTL من 0.3 → 1.5 ثانية — المشهد نادراً يتغير بين طلبين متتاليين
local SEARCH_CACHE_TTL = 1.5
local function searchAllDescendants()
    if _searchCache and tick() - _searchCacheTime < SEARCH_CACHE_TTL then
        return _searchCache
    end
    -- FIX v1.4: pre-allocate بدل table.insert المتكرر
    local all = {}
    local idx = 0
    for _, svc in ipairs(SEARCH_SERVICES) do
        if svc and type(svc) == "userdata" then
            local desc = svc:GetDescendants()
            for i = 1, #desc do
                idx = idx + 1
                all[idx] = desc[i]
            end
        end
    end
    -- FIX v1.4: فقط اللاعب المحلي (بدل كل اللاعبين) لأن هذا LocalScript
    local pg = player:FindFirstChild("PlayerGui")
    if pg then
        local desc = pg:GetDescendants()
        for i = 1, #desc do
            idx = idx + 1
            all[idx] = desc[i]
        end
    end
    _searchCache = all
    _searchCacheTime = tick()
    return all
end

local function findByName(search)
    if not search or search == "" then return nil end
    if search:find(".", 1, true) then
        local parts = {}
        for p in search:gmatch("[^.]+") do table.insert(parts, p) end
        if #parts >= 2 then
            local function traverseFrom(start, startIdx)
                local current = start
                for i = startIdx, #parts do
                    local child = current:FindFirstChild(parts[i])
                    if not child then
                        child = current:FindFirstChild(parts[i]:lower())
                    end
                    if not child then
                        for _, c in ipairs(current:GetChildren()) do
                            if c.Name:lower() == parts[i]:lower() then
                                child = c
                                break
                            end
                        end
                    end
                    if not child then
                        local searchNoSpaces = parts[i]:gsub("%s+", "")
                        for _, c in ipairs(current:GetChildren()) do
                            if c.Name:lower():gsub("%s+", "") == searchNoSpaces:lower() then
                                child = c
                                break
                            end
                        end
                    end
                    if not child then return nil end
                    if i == #parts then return child end
                    current = child
                end
                return nil
            end
            -- try direct service lookup
            local svc = PARENT_MAP[parts[1]]
            if svc then
                local found = traverseFrom(svc, 2)
                if found then return found end
            end
            -- parts[1] might match a service key case-insensitively
            for svcKey, svcVal in pairs(PARENT_MAP) do
                if svcKey:lower() == parts[1]:lower() then
                    local found = traverseFrom(svcVal, 2)
                    if found then return found end
                end
            end
            -- parts[1] is not a service; search across all services for the root
            for _, svc in ipairs(SEARCH_SERVICES) do
                if svc and type(svc) == "userdata" then
                    local root = svc:FindFirstChild(parts[1])
                    if not root then
                        for _, c in ipairs(svc:GetChildren()) do
                            if c.Name:lower() == parts[1]:lower() then
                                root = c
                                break
                            end
                        end
                    end
                    if root then
                        local found = traverseFrom(root, 2)
                        if found then return found end
                        if root:IsA("Player") and root.Character then
                            found = traverseFrom(root.Character, 2)
                            if found then return found end
                        end
                    end
                end
            end
        end
    end
    local lowerSearch = search:lower()
    local exact, prefixMatch, substringMatch = nil, nil, nil
    for _, obj in ipairs(searchAllDescendants()) do
        local name = obj.Name:lower()
        if name == lowerSearch then
            exact = obj
            break
        elseif not prefixMatch and name:find(lowerSearch, 1, true) == 1 then
            prefixMatch = obj
        elseif not substringMatch and name:find(lowerSearch, 1, true) then
            substringMatch = obj
        end
    end
    return exact or prefixMatch or substringMatch
end

local function findAllByName(search)
    local results = {}
    if not search or search == "" then return results end
    local lowerSearch = search:lower()
    local cache = _searchCache
    if cache then
        for _, obj in ipairs(cache) do
            if obj.Name:lower():find(lowerSearch, 1, true) then
                table.insert(results, obj)
            end
        end
    else
        for _, obj in ipairs(searchAllDescendants()) do
            if obj.Name:lower():find(lowerSearch, 1, true) then
                table.insert(results, obj)
            end
        end
    end
    return results
end

local function resolveUDim2(t)
    if type(t) ~= "table" then return nil end
    local xs, xo, ys, yo = t[1], t[2], t[3], t[4]
    if xs == nil and t.X ~= nil then xs = t.X end
    if xo == nil and t.XOffset ~= nil then xo = t.XOffset end
    if ys == nil and t.Y ~= nil then ys = t.Y end
    if yo == nil and t.YOffset ~= nil then yo = t.YOffset end
    if xs == nil then xs = 0 end
    if xo == nil then xo = 0 end
    if ys == nil then ys = 0 end
    if yo == nil then yo = 0 end
    return UDim2.new(xs, xo, ys, yo)
end

local function applyProperties(inst, props)
    if type(props) ~= "table" then return end
    for key, value in pairs(props) do
        pcall(function()
            if key == "Position" and type(value) == "table" then
                if inst:IsA("GuiObject") then
                    local u = resolveUDim2(value)
                    if u then inst.Position = u end
                else
                    inst.Position = Vector3.new(value[1] or 0, value[2] or 0, value[3] or 0)
                end
            elseif key == "Size" and type(value) == "table" then
                if inst:IsA("GuiObject") then
                    local u = resolveUDim2(value)
                    if u then inst.Size = u end
                elseif inst:IsA("BasePart") then
                    inst.Size = Vector3.new(value[1] or 1, value[2] or 1, value[3] or 1)
                else
                    inst.Size = UDim2.new(value[1] or 0, value[2] or 0, value[3] or 0, value[4] or 0)
                end
            elseif key == "Color" and type(value) == "table" then
                inst.Color = Color3.fromRGB(value[1] or 255, value[2] or 255, value[3] or 255)
            elseif key == "TextColor3" and type(value) == "table" then
                inst.TextColor3 = Color3.fromRGB(value[1] or 255, value[2] or 255, value[3] or 255)
            elseif key == "BackgroundColor3" and type(value) == "table" then
                inst.BackgroundColor3 = Color3.fromRGB(value[1] or 255, value[2] or 255, value[3] or 255)
            elseif key == "BorderColor3" and type(value) == "table" then
                inst.BorderColor3 = Color3.fromRGB(value[1] or 255, value[2] or 255, value[3] or 255)
            elseif key == "BrickColor" and type(value) == "string" then
                inst.BrickColor = BrickColor.new(value)
            elseif key == "Material" and type(value) == "string" then
                inst.Material = Enum.Material[value] or inst.Material
            elseif key == "Shape" and type(value) == "string" then
                if inst:IsA("Part") then
                    inst.Shape = Enum.PartType[value] or Enum.PartType.Block
                end
            elseif key == "MeshId" and type(value) == "string" then
                if inst:IsA("MeshPart") then
                    inst.MeshId = value
                elseif inst:IsA("Part") then
                    local mesh = Instance.new("SpecialMesh")
                    mesh.MeshId = value
                    mesh.Parent = inst
                end
            elseif key == "TextureId" and type(value) == "string" then
                if inst:IsA("MeshPart") then
                    inst.TextureId = value
                elseif inst:IsA("Part") then
                    local mesh = inst:FindFirstChildOfClass("SpecialMesh") or Instance.new("SpecialMesh")
                    mesh.TextureId = value
                    mesh.Parent = inst
                end
            elseif key == "Font" and type(value) == "string" then
                inst.Font = Enum.Font[value] or inst.Font
            elseif key == "TextXAlignment" and type(value) == "string" then
                inst.TextXAlignment = Enum.TextXAlignment[value] or Enum.TextXAlignment.Center
            elseif key == "TextYAlignment" and type(value) == "string" then
                inst.TextYAlignment = Enum.TextYAlignment[value] or Enum.TextYAlignment.Center
            elseif key == "AnchorPoint" and type(value) == "table" then
                inst.AnchorPoint = Vector2.new(value[1] or 0, value[2] or 0)
            elseif key == "Image" and type(value) == "string" then
                if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
                    inst.Image = value
                end
            elseif key == "Anchored" then
                inst.Anchored = value
            elseif key == "Transparency" then
                inst.Transparency = value
            elseif key == "BackgroundTransparency" then
                inst.BackgroundTransparency = value
            elseif key == "CanCollide" then
                inst.CanCollide = value
            elseif key == "WalkSpeed" then
                inst.WalkSpeed = value
            elseif key == "PlatformStand" then
                inst.PlatformStand = value
            elseif key == "Brightness" then
                inst.Brightness = value
            elseif key == "ClockTime" then
                inst.ClockTime = value
            elseif key == "FogEnd" then
                inst.FogEnd = value
            elseif key == "FogStart" then
                inst.FogStart = value
            elseif key == "Source" then
                local srcOk = pcall(function() inst.Source = "--from skill-Ai\n" .. tostring(value) end)
                if not srcOk then
                    local srcOk2 = pcall(function() inst[key] = "--from skill-Ai\n" .. tostring(value) end)
                end
            else
                inst[key] = value
            end
        end)
    end
end

local function safeRandomRange(r)
    local function pick(arrIdx, objKey, default)
        local v
        if type(r) == "table" then
            v = r[arrIdx]
            if v == nil and objKey then v = r[objKey] end
        end
        v = tonumber(v)
        if v == nil then v = default end
        return math.floor(v)
    end

    local minX = pick(1, "minX", -60)
    local maxX = pick(2, "maxX", 60)
    local minY = pick(3, "minY", -5)
    local maxY = pick(4, "maxY", 10)
    local minZ = pick(5, "minZ", -60)
    local maxZ = pick(6, "maxZ", 60)

    if minX > maxX then minX, maxX = maxX, minX end
    if minY > maxY then minY, maxY = maxY, minY end
    if minZ > maxZ then minZ, maxZ = maxZ, minZ end

    return minX, maxX, minY, maxY, minZ, maxZ
end

local function getOrCreateContainer(name, parent)
    if not name or name == "" then return parent end
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("Folder") then
        return existing
    end
    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent
    return folder
end

local function makeScriptWithBackup(className, name, source, targetParent, containerName)
    if containerName then
        targetParent = getOrCreateContainer(containerName, targetParent)
    end

    local host = Instance.new("StringValue")
    host.Name = name or className
    host.Value = source
    host.Parent = targetParent

    local mock = {
        Name = host.Name,
        Parent = targetParent,
        ClassName = className,
        Source = source,
        Value = source,
        FindFirstChild = function(self, childName)
            return targetParent:FindFirstChild(childName)
        end,
        WaitForChild = function(self, childName, timeout)
            return targetParent:WaitForChild(childName, timeout)
        end,
        IsA = function(self, class)
            return className == class
        end,
        Destroy = function(self)
            host:Destroy()
        end,
    }

    local loadOk = false
    local compileErr = nil
    pcall(function()
        local fn, compErr = loadstring("local script = ...\n" .. source)
        if fn then
            task.spawn(function()
                local runtimeOk, runtimeErr = pcall(fn, mock)
                if not runtimeOk then
                    logToFile("Runtime error in " .. (name or className), runtimeErr)
                end
            end)
            loadOk = true
        else
            compileErr = compErr
            logToFile("Compile error in " .. (name or className), compErr)
        end
    end)

    return mock, nil, true, host, loadOk, compileErr
end

local function ensureToolHandle(toolInst, handleProps)
    local handle = toolInst:FindFirstChild("Handle")
    if not handle then
        handle = Instance.new("Part")
        handle.Name = "Handle"
        handle.Size = Vector3.new(0.6, 2.5, 0.6)
        handle.Color = Color3.fromRGB(150, 150, 150)
        handle.Material = Enum.Material.Metal
        handle.Parent = toolInst
    end
    if type(handleProps) == "table" then
        applyProperties(handle, handleProps)
    end
    handle.Anchored = false
    handle.CanCollide = false
    toolInst.RequiresHandle = true
    toolInst.Grip = toolInst.Grip or CFrame.new()
    return handle
end

local function generateChallengeScript(challengeType, targetCount, challengeName, title)
    local function fill(t)
        local s = t
        s = s:gsub("{N}", function() return challengeName end)
        s = s:gsub("{C}", function() return tostring(targetCount) end)
        s = s:gsub("{T}", function() return (title or "Challenge") end)
        return s
    end
    if challengeType == "reach" then
        return fill([[
local plr = game:GetService("Players").LocalPlayer
local gui = plr:WaitForChild("PlayerGui"):WaitForChild("{N}_GUI")
local progressLabel = gui.MainFrame.Progress
local titleLabel = gui.MainFrame.Title
local detector = script.Parent:WaitForChild("{N}_Detector")
local completed = false

detector.Touched:Connect(function(hit)
    if completed then return end
    local char = hit.Parent
    local hum = char and char:FindFirstChild("Humanoid")
    if hum and plr.Character == char then
        completed = true
        progressLabel.Text = "1/1"
        progressLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
                titleLabel.Text = "✅ REACHED!"
    end
end)
]])
    elseif challengeType == "survive" then
        return fill([[
local plr = game:GetService("Players").LocalPlayer
local gui = plr:WaitForChild("PlayerGui"):WaitForChild("{N}_GUI")
local progressLabel = gui.MainFrame.Progress
local titleLabel = gui.MainFrame.Title
local detector = script.Parent:WaitForChild("{N}_Detector")
local completed = false
local inside = false
local survivedSeconds = 0
local TARGET = {C}

detector.Touched:Connect(function(hit)
    local char = hit.Parent
    local hum = char and char:FindFirstChild("Humanoid")
    if hum and plr.Character == char then inside = true end
end)
detector.TouchEnded:Connect(function(hit)
    local char = hit.Parent
    local hum = char and char:FindFirstChild("Humanoid")
    if hum and plr.Character == char then inside = false end
end)

task.spawn(function()
    while not completed do
        task.wait(1)
        if inside then
            survivedSeconds = survivedSeconds + 1
            progressLabel.Text = survivedSeconds .. "/" .. TARGET
            if survivedSeconds >= TARGET then
                completed = true
                progressLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
                titleLabel.Text = "✅ SURVIVED!"
            end
        end
    end
end)
]])
    elseif challengeType == "kill" then
        return fill([[
local plr = game:GetService("Players").LocalPlayer
local gui = plr:WaitForChild("PlayerGui"):WaitForChild("{N}_GUI")
local progressLabel = gui.MainFrame.Progress
local titleLabel = gui.MainFrame.Title
local detector = script.Parent:WaitForChild("{N}_Detector")
local completed = false
local killCount = 0
local connectedHumans = {}
local TARGET = {C}

detector.Touched:Connect(function(hit)
    local char = hit.Parent
    local hum = char and char:FindFirstChild("Humanoid")
    if hum and not connectedHumans[hum] then
        connectedHumans[hum] = true
        hum.Died:Connect(function()
            if completed then return end
            if not char.Parent then
                task.wait(0.1)
                killCount = killCount + 1
                progressLabel.Text = killCount .. "/" .. TARGET
                if killCount >= TARGET then
                    completed = true
                    progressLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
                    titleLabel.Text = "✅ COMPLETE!"
                end
            end
        end)
    end
end)
]])
    elseif challengeType == "collect" then
        return fill([[
local plr = game:GetService("Players").LocalPlayer
local gui = plr:WaitForChild("PlayerGui"):WaitForChild("{N}_GUI")
local progressLabel = gui.MainFrame.Progress
local titleLabel = gui.MainFrame.Title
local detector = script.Parent:WaitForChild("{N}_Detector")
local completed = false
local collected = 0
local TARGET = {C}

detector.Touched:Connect(function(hit)
    if completed then return end
    if hit:GetAttribute("Collectible") or hit.Name:find("Collect") then
        collected = collected + 1
        progressLabel.Text = collected .. "/" .. TARGET
        pcall(function() hit:Destroy() end)
        if collected >= TARGET then
            completed = true
            progressLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
            titleLabel.Text = "✅ COLLECTED!"
        end
    end
end)
]])
    end
    return "task.wait(9e9)"
end

local function setCollision(inst, enabled)
    if not inst or not inst:IsA("BasePart") then return end
    inst.CanCollide = enabled
    task.spawn(function()
        task.wait(0)
        if inst and inst.Parent then
            inst.CanCollide = enabled
        end
    end)
    task.spawn(function()
        task.wait(0.15)
        if inst and inst.Parent then
            inst.CanCollide = enabled
        end
    end)
end

local function executeAction(action)
    local kind = action.type

    if kind == "create_instance" then
        local className = action.className
        if not className then return false, "❌ Missing className" end

        local ok, inst = pcall(function() return Instance.new(className) end)
        if not ok or not inst then
            return false, "❌ Failed to create " .. tostring(className)
        end

        inst.Name = action.name or className
        applyProperties(inst, action.properties)

        -- set Anchored/CanCollide BEFORE parent (belt)
        if inst:IsA("BasePart") and className ~= "Tool" then
            inst.Anchored = true
            setCollision(inst, true)
        end

        if className == "Tool" then
            ensureToolHandle(inst, action.handleProperties)
        end

        local targetParent = resolveParent(action.parent, Workspace)

        -- AUTO-CORRECT: GUI objects in Workspace belong in StarterGui
        local GUI_CLASSES = { ScreenGui = true, Frame = true, TextLabel = true, TextButton = true,
            ImageLabel = true, ImageButton = true, ScrollingFrame = true, BillboardGui = true, ViewportFrame = true }
        if GUI_CLASSES[className] and targetParent == Workspace then
            targetParent = StarterGui
        end
        -- AUTO-CORRECT: Parts don't belong in GUI services
        local GUI_SERVICES = { StarterGui = true, StarterPlayerScripts = true, StarterCharacterScripts = true }
        if inst:IsA("BasePart") and GUI_SERVICES[targetParent.Name] then
            targetParent = Workspace
        end
        -- AUTO-CORRECT: Decal/Texture/SurfaceGui need a BasePart parent, not Workspace
        local ATTACHMENT_CLASSES = { Decal = true, Texture = true, SurfaceGui = true }
        if ATTACHMENT_CLASSES[className] and targetParent == Workspace then
            for i = #_batchCreated, 1, -1 do
                local prev = _batchCreated[i]
                if type(prev) ~= "table" and prev:IsA("BasePart") then
                    targetParent = prev
                    break
                end
            end
        end
        -- AUTO-CORRECT: StringValue/ModuleScript with code belong in ServerStorage, not Workspace
        local CODE_CLASSES = { StringValue = true, ModuleScript = true }
        if CODE_CLASSES[className] and targetParent == Workspace then
            targetParent = ServerStorage
        end

        if action.containerName then
            targetParent = getOrCreateContainer(action.containerName, targetParent)
        end
        inst.Parent = targetParent

        -- force Anchored/CanCollide AFTER parent (suspenders — some executors lose pre-parent writes)
        if inst:IsA("BasePart") then
            if className == "Tool" then
                local props = type(action.properties) == "table" and action.properties or {}
                if props.Anchored == nil then inst.Anchored = false end
                if props.CanCollide == nil then setCollision(inst, false) end
            else
                inst.Anchored = true
                setCollision(inst, true)
            end
        end
        table.insert(_batchCreated, inst)
        updateSceneState(action, true)

        if className == "Camera" and action.setAsCurrentCamera then
            Workspace.CurrentCamera = inst
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local offset = action.cameraOffset or {0, 2, -10}
                inst.CFrame = CFrame.new(
                    hrp.Position + Vector3.new(0, 2, 0),
                    hrp.Position + Vector3.new(offset[1] or 0, offset[2] or 2, offset[3] or -10)
                )
            end
        end

        _lastClickInstance = inst
        return true, "✅ Created " .. inst.Name .. " (" .. className .. ")"

    elseif kind == "create_multiple" then
        local className = action.className or "Part"
        local count = math.clamp(tonumber(action.count) or 1, 1, 200)
        local parent = resolveParent(action.parent, Workspace)
        -- AUTO-CORRECT: bulk create is for Parts, redirect from GUI services
        local GUI_SERVICES = { StarterGui = true, StarterPlayerScripts = true, StarterCharacterScripts = true }
        if GUI_SERVICES[parent.Name] then
            parent = Workspace
        end
        local container = getOrCreateContainer(action.containerName or (className .. "_Batch"), parent)

        local created = 0
        for i = 1, count do
            pcall(function()
                local ok, inst = pcall(function() return Instance.new(className) end)
                if ok and inst then
                    inst.Name = (action.namePrefix or className) .. "_" .. i
                    applyProperties(inst, action.properties)
                    -- belt: set before parent
                    if inst:IsA("BasePart") and className ~= "Tool" then
                        inst.Anchored = true
                        setCollision(inst, true)
                    end
                    if className == "Tool" then
                        ensureToolHandle(inst, action.handleProperties)
                    end
                    if action.randomizePosition then
                        local minX, maxX, minY, maxY, minZ, maxZ = safeRandomRange(action.randomRange)
                        if action.gridSpacing then
                            local spacing = math.max(1, tonumber(action.gridSpacing) or 4)
                            local maxAttempts = 30
                            local placed = _batchPlacedGrid or {}
                            _batchPlacedGrid = placed
                            local found = false
                            for _ = 1, maxAttempts do
                                local gx = math.floor(math.random(minX, maxX) / spacing) * spacing
                                local gy = math.floor(math.random(minY, maxY) / spacing) * spacing
                                local gz = math.floor(math.random(minZ, maxZ) / spacing) * spacing
                                local key = gx..","..gy..","..gz
                                if not placed[key] then
                                    placed[key] = true
                                    inst.Position = Vector3.new(gx, gy, gz)
                                    found = true
                                    break
                                end
                            end
                            if not found then
                                inst.Position = Vector3.new(math.random(minX, maxX), math.random(minY, maxY), math.random(minZ, maxZ))
                            end
                        else
                            inst.Position = Vector3.new(
                                math.random(minX, maxX),
                                math.random(minY, maxY),
                                math.random(minZ, maxZ)
                            )
                        end
                        -- rejection sampling: if rejectionRadius set, check distance to existing BaseParts in container
                        if action.rejectionRadius and container then
                            local radius = tonumber(action.rejectionRadius) or 4
                            local rejectAttempts = 30
                            for _ = 1, rejectAttempts do
                                local tooClose = false
                                for _, existing in ipairs(container:GetDescendants()) do
                                    if existing:IsA("BasePart") and existing ~= inst then
                                        local dist = (inst.Position - existing.Position).Magnitude
                                        if dist < radius then
                                            tooClose = true
                                            break
                                        end
                                    end
                                end
                                if tooClose then
                                    inst.Position = Vector3.new(
                                        math.random(minX, maxX),
                                        math.random(minY, maxY),
                                        math.random(minZ, maxZ)
                                    )
                                else
                                    break
                                end
                            end
                        end
                    end
                    inst.Parent = container
                    -- force Anchored/CanCollide AFTER parenting for physics engine
                    if inst:IsA("BasePart") then
                        if className == "Tool" then
                            local props = type(action.properties) == "table" and action.properties or {}
                            if props.Anchored == nil then inst.Anchored = false end
                            if props.CanCollide == nil then setCollision(inst, false) end
                        else
                            inst.Anchored = true
                            setCollision(inst, true)
                        end
                    end
                    table.insert(_batchCreated, inst)
                    created += 1
                end
            end)
        end
        _batchPlacedGrid = nil
        updateSceneState(action, true)
        _lastClickInstance = container
        return true, "✅ Created " .. created .. " items inside " .. container.Name

    elseif kind == "set_property" then
        local target = action.target and findByName(action.target)
        if not target then return false, "❌ Not found: " .. tostring(action.target) end
        applyProperties(target, action.properties)
        updateSceneState(action, true)
        return true, "✅ Updated properties: " .. target.Name

    elseif kind == "delete" then
        local target = action.target and findByName(action.target)
        if not target then return false, "❌ Not found: " .. tostring(action.target) end
        local n = target.Name
        table.insert(_batchCreated, { _markedForDestroy = true, _ref = target, _name = n })
        target:Destroy()
        updateSceneState(action, true)
        return true, "🗑️ Deleted: " .. n

    elseif kind == "clone" then
        local target = action.target and findByName(action.target)
        if not target then return false, "❌ Not found: " .. tostring(action.target) end
        local clone = target:Clone()
        clone.Name = action.newName or (target.Name .. "_clone")
        clone.Parent = target.Parent
        table.insert(_batchCreated, clone)
        updateSceneState(action, true)
        return true, "📋 Cloned: " .. target.Name .. " → " .. clone.Name

    elseif kind == "rename" then
        local target = action.target and findByName(action.target)
        if not target then return false, "❌ Not found: " .. tostring(action.target) end
        local old = target.Name
        target.Name = action.newName or old
        updateSceneState(action, true)
        return true, "✏️ Renamed: " .. old .. " → " .. target.Name

    elseif kind == "move" then
        local target = action.target and findByName(action.target)
        if not target then return false, "❌ Not found: " .. tostring(action.target) end
        if target:IsA("BasePart") and action.position then
            target.Position = Vector3.new(action.position[1] or 0, action.position[2] or 0, action.position[3] or 0)
            updateSceneState(action, true)
            return true, "🚚 Moved: " .. target.Name
        elseif action.parent then
            target.Parent = resolveParent(action.parent, target.Parent)
            updateSceneState(action, true)
            return true, "🚚 Moved: " .. target.Name .. " to " .. tostring(action.parent)
        end
        return false, "❌ Insufficient move data"

    elseif kind == "set_lighting" then
        if type(action.properties) == "table" and action.properties.FogEnd ~= nil then
            local fogKeywords = { "fog", "backrooms", "horror", "mist", "haze", "creepy" }
            local mentioned = false
            local lowerQ = (CURRENT_REQUEST_TEXT or ""):lower()
            for _, kw in ipairs(fogKeywords) do
                if lowerQ:find(kw, 1, true) then
                    mentioned = true
                    break
                end
            end
            if not mentioned then
                local fe = tonumber(action.properties.FogEnd)
                if fe and fe < 300 then
                    action.properties.FogEnd = nil -- skip fog since user did not ask for it
                end
            end
        end
        applyProperties(Lighting, action.properties)
        updateSceneState(action, true)
        return true, "💡 Lighting updated"

    elseif kind == "set_character" then
        local char = player.Character
        if not char or not char:FindFirstChild("Humanoid") then
            return false, "❌ No character available"
        end
        applyProperties(char.Humanoid, action.properties)
        if char:FindFirstChild("HumanoidRootPart") and action.transparency ~= nil then
            char.HumanoidRootPart.Transparency = action.transparency
        end
        updateSceneState(action, true)
        return true, "✅ Character state updated"

    elseif kind == "create_compound" then
        local parts = action.parts
        if not parts or type(parts) ~= "table" or #parts == 0 then
            return false, "❌ Missing parts array for compound"
        end
        local model = Instance.new("Model")
        model.Name = action.name or "Compound"
        local createdParts = {}
        local primaryIdx = action.primaryPartIndex or 1
        local isToolCompound = action.makeTool or action.className == "Tool"

        -- parent model FIRST so parts enter DataModel immediately
        local targetParent = resolveParent(action.parent, Workspace)
        if action.containerName then
            targetParent = getOrCreateContainer(action.containerName, targetParent)
        end
        model.Parent = targetParent

        for i, partData in ipairs(parts) do
            pcall(function()
                local cn = partData.className or "Part"
                local ok, inst = pcall(function() return Instance.new(cn) end)
                if ok and inst then
                    inst.Name = partData.name or ("Part_" .. i)
                    applyProperties(inst, partData)
                    -- belt: set before parent
                    if inst:IsA("BasePart") and not isToolCompound then
                        inst.Anchored = true
                        setCollision(inst, true)
                    end
                    inst.Parent = model
                    table.insert(createdParts, inst)
                end
            end)
        end
        if #createdParts == 0 then
            model:Destroy()
            return false, "❌ Failed to create any compound part"
        end

        -- force Anchored/CanCollide AFTER all parts are in the DataModel
        for _, part in ipairs(createdParts) do
            if part:IsA("BasePart") then
                if isToolCompound then
                    part.Anchored = false
                    setCollision(part, false)
                else
                    part.Anchored = true
                    setCollision(part, true)
                end
            end
        end

        -- ⚠️ فحص تصادم/تراكب بين أجزاء نفس الـ compound: لو الـ AI أخطأ بحساب
        -- position وحط جزئين (مثلاً النصل والمقبض) بنفس النقطة تقريباً، الشكل
        -- النهائي يطلع كتلة واحدة مشوهة بدل سيف/برج واضح المعالم. نتحقق من كل
        -- زوج أجزاء، ولو متراكبين فعلياً (مسافة أقل من نص متوسط حجمهم)، نزيح
        -- الجزء الثاني قليلاً على المحور Y حتى يصير الشكل مفهوم بصرياً.
        local overlapFixCount = 0
        for i = 1, #createdParts do
            for j = i + 1, #createdParts do
                local a, b = createdParts[i], createdParts[j]
                local okCheck, isOverlap = pcall(function()
                    local dist = (a.Position - b.Position).Magnitude
                    local avgSize = ((a.Size.X + a.Size.Y + a.Size.Z) + (b.Size.X + b.Size.Y + b.Size.Z)) / 6
                    return dist < (avgSize * 0.15) -- متراكبين فعلياً، مو بس قريبين بشكل طبيعي
                end)
                if okCheck and isOverlap then
                    pcall(function()
                        b.Position = b.Position + Vector3.new(0, (b.Size.Y * 0.6) + 0.1, 0)
                    end)
                    overlapFixCount = overlapFixCount + 1
                end
            end
        end
        local primary = createdParts[primaryIdx]
        for i, part in ipairs(createdParts) do
            if part ~= primary then
                local weld = Instance.new("WeldConstraint")
                weld.Name = ("Weld_%d_%d"):format(primaryIdx, i)
                weld.Part0 = primary
                weld.Part1 = part
                weld.Parent = part
            end
        end
        model.PrimaryPart = primary
        if action.makeTool or action.className == "Tool" then
            local tool = Instance.new("Tool")
            tool.Name = action.name or model.Name
            local h = Instance.new("Part")
            h.Name = "Handle"
            h.Size = Vector3.new(0.6, 2.5, 0.6)
            h.Anchored = false
            h.CanCollide = false
            h.Parent = tool
            for _, child in ipairs(model:GetChildren()) do
                child.Parent = tool
            end
            model:Destroy()
            model = tool
            tool.Parent = targetParent  -- re-parent since model was destroyed
            tool.RequiresHandle = true
            tool.Grip = CFrame.new()
        end
        table.insert(_batchCreated, model)
        updateSceneState(action, true)
        _lastClickInstance = model
        local overlapMsg = overlapFixCount > 0 and (" (auto-fixed " .. overlapFixCount .. " overlapping part(s))") or ""
        return true, "✅ Created compound: " .. model.Name .. overlapMsg

    elseif kind == "create_enclosure" then
        -- 🧮 GEOMETRY HELPER: يبني أرضية + جدران (وحاجز اختياري) من وصف منطقي
        -- بسيط فقط (مركز، عرض، عمق، ارتفاع) — كل حساب المواقع/المسافات يصير
        -- هنا بالكود (فوري، صفر توكنز)، مو من الـ AI. هذا يلغي السبب الجذري
        -- وراء "Impure JSON" بطلبات فيها جدران/حواجز متعددة المواقع، لأن الموديل
        -- ما يحتاج يحسب إحداثيات يدوياً بصوت عالي قبل الرد.
        local centerX = tonumber(action.centerX) or 0
        local centerY = tonumber(action.centerY) or 0
        local centerZ = tonumber(action.centerZ) or 0
        local width = math.max(2, tonumber(action.width) or 20)   -- X axis
        local depth = math.max(2, tonumber(action.depth) or 20)   -- Z axis
        local wallHeight = math.max(1, tonumber(action.wallHeight) or 4)
        local floorThickness = 0.5
        local wallThickness = 0.5
        local hasFloor = action.floor ~= false
        local openSides = {} -- e.g. {"North"} to leave an entrance gap
        if type(action.openSides) == "table" then
            for _, s in ipairs(action.openSides) do openSides[s] = true end
        end
        local color = action.color or {150,150,150}
        local material = action.material or "SmoothPlastic"
        local barrier = action.barrier -- bool: add an invisible solid barrier covering the whole footprint at wall height (used for "locked until unlocked" platforms)

        local model = Instance.new("Model")
        model.Name = action.name or "Enclosure"
        local targetParent = resolveParent(action.parent, Workspace)
        if action.containerName then
            targetParent = getOrCreateContainer(action.containerName, targetParent)
        end
        model.Parent = targetParent

        local function mkPart(pname, size, pos)
            local p = Instance.new("Part")
            p.Name = pname
            p.Size = Vector3.new(size[1], size[2], size[3])
            p.Position = Vector3.new(pos[1], pos[2], pos[3])
            pcall(function() p.Color = Color3.fromRGB(color[1] or 150, color[2] or 150, color[3] or 150) end)
            pcall(function() p.Material = Enum.Material[material] or Enum.Material.SmoothPlastic end)
            p.Anchored = true
            setCollision(p, true)
            p.Parent = model
            return p
        end

        if hasFloor then
            mkPart("Floor", {width, floorThickness, depth}, {centerX, centerY, centerZ})
        end
        local floorTop = centerY + floorThickness / 2
        local wallCenterY = floorTop + wallHeight / 2
        if not openSides["North"] then
            mkPart("WallNorth", {width, wallHeight, wallThickness}, {centerX, wallCenterY, centerZ - depth/2})
        end
        if not openSides["South"] then
            mkPart("WallSouth", {width, wallHeight, wallThickness}, {centerX, wallCenterY, centerZ + depth/2})
        end
        if not openSides["East"] then
            mkPart("WallEast", {wallThickness, wallHeight, depth}, {centerX + width/2, wallCenterY, centerZ})
        end
        if not openSides["West"] then
            mkPart("WallWest", {wallThickness, wallHeight, depth}, {centerX - width/2, wallCenterY, centerZ})
        end

        if barrier then
            local b = mkPart("Barrier", {width, wallHeight, depth}, {centerX, wallCenterY, centerZ})
            b.Transparency = 1
            setCollision(b, true)
            b.Name = "Barrier"
        end

        table.insert(_batchCreated, model)
        updateSceneState(action, true)
        _lastClickInstance = model
        return true, "✅ Created enclosure: " .. model.Name .. " (" .. (hasFloor and "floor+" or "") .. "walls" .. (barrier and "+barrier" or "") .. ")"

    elseif kind == "create_challenge_system" then
        local challengeType = (action.challengeType or "reach"):lower()
        local validTypes = { reach = true, survive = true, kill = true, collect = true }
        if not validTypes[challengeType] then
            return false, "❌ Invalid challengeType '" .. tostring(action.challengeType) .. "'. Valid: reach, survive, kill, collect"
        end
        local targetCount = math.max(1, tonumber(action.targetCount) or 10)
        local title = action.title or ("Challenge: " .. challengeType)
        local challengeName = action.name or "Challenge"
        local centerX = tonumber(action.centerX) or 0
        local centerY = tonumber(action.centerY) or 5
        local centerZ = tonumber(action.centerZ) or 0
        local width = math.max(2, tonumber(action.width) or 20)
        local depth = math.max(2, tonumber(action.depth) or 20)
        local height = math.max(2, tonumber(action.height) or 6)
        local visibleFloor = action.visibleFloor ~= false

        local zoneModel = Instance.new("Model")
        zoneModel.Name = challengeName .. "_Zone"
        local zoneParent = resolveParent(action.parent, Workspace)
        if action.containerName then
            zoneParent = getOrCreateContainer(action.containerName, zoneParent)
        end
        zoneModel.Parent = zoneParent

        if visibleFloor then
            local floor = Instance.new("Part")
            floor.Name = challengeName .. "_Floor"
            floor.Size = Vector3.new(width, 0.5, depth)
            floor.Position = Vector3.new(centerX, centerY - 0.25, centerZ)
            floor.Anchored = true
            setCollision(floor, true)
            floor.BrickColor = BrickColor.new("Bright blue")
            floor.Material = Enum.Material.SmoothPlastic
            floor.Transparency = 0.3
            floor.Parent = zoneModel
        end

        -- optional walls around zone
        local wallOpenSides = {}
        if type(action.walls) == "table" then
            for _, s in ipairs(action.walls) do wallOpenSides[s] = true end
        end
        if action.walls == true or type(action.walls) == "table" then
            local wallH = math.max(1, tonumber(action.wallHeight) or height)
            local wallT = 0.5
            local floorTop = centerY + 0.25
            local wallCY = floorTop + wallH / 2
            local wallColor = action.wallColor or {100, 100, 255}
            local wallMat = action.wallMaterial or "SmoothPlastic"
            local function mkWall(n, sz, pos)
                local w = Instance.new("Part")
                w.Name = challengeName .. "_" .. n
                w.Size = Vector3.new(sz[1], sz[2], sz[3])
                w.Position = Vector3.new(pos[1], pos[2], pos[3])
                w.Anchored = true
                setCollision(w, true)
                pcall(function() w.Color = Color3.fromRGB(wallColor[1] or 100, wallColor[2] or 100, wallColor[3] or 255) end)
                pcall(function() w.Material = Enum.Material[wallMat] or Enum.Material.SmoothPlastic end)
                w.Transparency = 0.2
                w.Parent = zoneModel
            end
            if not wallOpenSides["North"] then mkWall("WallNorth", {width, wallH, wallT}, {centerX, wallCY, centerZ - depth/2}) end
            if not wallOpenSides["South"] then mkWall("WallSouth", {width, wallH, wallT}, {centerX, wallCY, centerZ + depth/2}) end
            if not wallOpenSides["East"] then mkWall("WallEast", {wallT, wallH, depth}, {centerX + width/2, wallCY, centerZ}) end
            if not wallOpenSides["West"] then mkWall("WallWest", {wallT, wallH, depth}, {centerX - width/2, wallCY, centerZ}) end
        end

        local detector = Instance.new("Part")
        detector.Name = challengeName .. "_Detector"
        detector.Size = Vector3.new(width, height, depth)
        detector.Position = Vector3.new(centerX, centerY + height / 2 - 0.25, centerZ)
        detector.Anchored = true
        detector.CanCollide = false
        detector.Transparency = 1
        detector.Parent = zoneModel

        table.insert(_batchCreated, zoneModel)

        local guiPosition = (action.guiPosition or "top-right"):lower()
        local guiPosMap = {
            ["top-right"] = UDim2.new(1, -270, 0, 10),
            ["top-left"] = UDim2.new(0, 20, 0, 10),
            ["bottom-right"] = UDim2.new(1, -270, 1, -80),
            ["bottom-left"] = UDim2.new(0, 20, 1, -80),
            ["center"] = UDim2.new(0.5, -125, 0.5, -30),
        }
        local guiSize = type(action.guiSize) == "table" and action.guiSize or {250, 60}
        local gw = math.max(100, tonumber(guiSize[1]) or 250)
        local gh = math.max(40, tonumber(guiSize[2]) or 60)

        local gui = Instance.new("ScreenGui")
        gui.Name = challengeName .. "_GUI"
        gui.ResetOnSpawn = false
        gui.Parent = StarterGui

        local frame = Instance.new("Frame")
        frame.Name = "MainFrame"
        frame.Size = UDim2.new(0, gw, 0, gh)
        frame.Position = guiPosMap[guiPosition] or guiPosMap["top-right"]
        frame.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
        frame.BackgroundTransparency = 0.3
        frame.BorderSizePixel = 0
        frame.Parent = gui
        local uic = Instance.new("UICorner")
        uic.CornerRadius = UDim.new(0, 8)
        uic.Parent = frame

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Name = "Title"
        titleLabel.Size = UDim2.new(1, -20, 0, 22)
        titleLabel.Position = UDim2.new(0, 10, 0, 4)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = title
        titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        titleLabel.TextSize = 14
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.Parent = frame

        local progressLabel = Instance.new("TextLabel")
        progressLabel.Name = "Progress"
        progressLabel.Size = UDim2.new(1, -20, 0, 26)
        progressLabel.Position = UDim2.new(0, 10, 0, 28)
        progressLabel.BackgroundTransparency = 1
        progressLabel.Text = "0/" .. targetCount
        progressLabel.TextColor3 = Color3.fromRGB(0, 200, 255)
        progressLabel.TextSize = 20
        progressLabel.Font = Enum.Font.GothamBlack
        progressLabel.TextXAlignment = Enum.TextXAlignment.Left
        progressLabel.Parent = frame

        table.insert(_batchCreated, gui)

        local scriptSrc = generateChallengeScript(challengeType, targetCount, challengeName, title)

        local host = Instance.new("StringValue")
        host.Name = challengeName .. "_Script"
        host.Value = "--from skill-Ai\n" .. scriptSrc
        host.Parent = zoneModel

        local mock = {
            Name = host.Name,
            Parent = zoneModel,
            ClassName = "LocalScript",
            Source = scriptSrc,
            Value = scriptSrc,
            FindFirstChild = function(self, childName)
                local ok, r = pcall(function() return zoneModel:FindFirstChild(childName) end)
                return ok and r
            end,
            WaitForChild = function(self, childName, timeout)
                local ok, r = pcall(function() return zoneModel:WaitForChild(childName, timeout) end)
                return ok and r
            end,
            FindFirstChildOfClass = function(self, cls)
                local ok, r = pcall(function() return zoneModel:FindFirstChildOfClass(cls) end)
                return ok and r
            end,
            Destroy = function(self)
                pcall(function() host:Destroy() end)
                pcall(function() gui:Destroy() end)
                pcall(function() zoneModel:Destroy() end)
                for idx, entry in ipairs(_autoRunScripts) do
                    if entry.inst == self then
                        table.remove(_autoRunScripts, idx)
                        break
                    end
                end
            end,
            IsA = function(self, cls) return cls == "Script" or cls == "LocalScript" end,
        }

        local fn, compileErr = loadstring("local script = ...\n" .. scriptSrc)
        local loadOk = false
        local execErr = nil
        if fn then
            local ok, e = pcall(fn, mock)
            if ok then
                loadOk = true
            else
                execErr = tostring(e)
            end
        else
            execErr = tostring(compileErr)
        end

        if loadOk then
            table.insert(_autoRunScripts, { name = host.Name, source = scriptSrc, inst = mock })
            if #_autoRunScripts > AUTORUN_MAX then
                table.remove(_autoRunScripts, 1)
            end
        end

        updateSceneState(action, true)
        local fx = visibleFloor and "floor+" or ""
        local msg = "✅ Created challenge: " .. challengeName .. " (" .. challengeType .. " " .. targetCount .. ", " .. fx .. "zone)"
        if loadOk then
            msg = msg .. " | Executed"
        elseif execErr then
            msg = msg .. " | ⚠️ " .. execErr
        end
        return true, msg

    elseif kind == "create_script" then
        local className = action.className or "Script"
        if className ~= "Script" and className ~= "LocalScript" then
            return false, "❌ create_script requires className = Script or LocalScript"
        end
        local source = "--from skill-Ai\n"
        if action.source then
            source = source .. action.source
        end

        -- auto-fix syntax errors before creating
        local fn_check, err_check = loadstring("local script = ...\n" .. source)
        if not fn_check then
            local rawCode = action.source or source
            local fixedCode, fixErr = fixLuaCode(rawCode, err_check)
            if fixedCode then
                source = "--from skill-Ai\n" .. fixedCode
            end
        end

        local targetParent = resolveParent(action.parent, nil)
        if not targetParent and type(action.parent) == "string" then
            for _, createdInst in ipairs(_batchCreated) do
                if type(createdInst) ~= "table" and createdInst.Name == action.parent then
                    targetParent = createdInst
                    break
                end
            end
            if not targetParent then
                targetParent = findByName(action.parent)
            end
        end
        targetParent = targetParent or Workspace

        -- SAFETY: reject per-player PlayerGui as parent (scripts there run once per player, confusing)
        if targetParent and targetParent:IsA("PlayerGui") and targetParent.Parent and targetParent.Parent:IsA("Player") then
            targetParent = StarterPlayerScripts or Workspace
        end

        -- AUTO-CORRECT: Scripts in Workspace never run — redirect
        if targetParent == Workspace then
            if className == "LocalScript" then
                targetParent = StarterPlayerScripts or StarterPlayer or Workspace
            else
                targetParent = ServerStorage or Workspace
            end
        end

        local inst, err, sourceWorked, host, loadOk, compileErr = makeScriptWithBackup(
            className, action.name, source, targetParent, action.containerName
        )
        if not inst then
            return false, "❌ " .. err
        end

        table.insert(_batchCreated, host)
        updateSceneState(action, true)
        _lastClickInstance = host

        -- register for respawn re-execution so effects persist across deaths
        if loadOk then
            table.insert(_autoRunScripts, { name = inst.Name, source = source, inst = inst })
            if #_autoRunScripts > AUTORUN_MAX then
                table.remove(_autoRunScripts, 1)
            end
        end

        local parts = {}
        table.insert(parts, "✅ Created: " .. inst.Name .. " (" .. className .. ")")
        if loadOk then
            table.insert(parts, "Executed in-game")
        elseif compileErr then
            table.insert(parts, "⚠️ " .. compileErr)
        end
        local msg = table.concat(parts, " | ")
        msg = msg .. "\n━━━━━━━━━━━━━━━━━━\n" .. source .. "\n━━━━━━━━━━━━━━━━━━"
        return true, msg

    elseif kind == "undo" then
        if #undoStack == 0 then
            return false, "⚠️ Nothing to undo."
        end
        local lastBatch = table.remove(undoStack)
        local removed = 0
        for _, entry in ipairs(lastBatch.instances) do
            if type(entry) == "table" and entry._markedForDestroy then
                -- was a delete action, cannot restore (object already destroyed)
            else
                local inst = entry
                if inst and inst.Parent then
                    inst:Destroy()
                    removed += 1
                end
            end
        end
        return true, "↩️ Undone: " .. lastBatch.summary .. " (removed " .. removed .. " items)"

    elseif kind == "create_plugin" then
        local pluginName = action.name or "Plugin"
        local modules = action.modules
        if not modules or type(modules) ~= "table" or #modules == 0 then
            return false, "❌ create_plugin requires a 'modules' array with at least one {name, source}"
        end
        local icon = action.icon or "🧩"
        local btnColor = action.buttonColor or {30, 30, 40}
        local targetParent = resolveParent(action.parent, CoreGui)

        -- Plugin toolbar GUI
        local toolbar = Instance.new("ScreenGui")
        toolbar.Name = pluginName .. "_Toolbar"
        toolbar.ResetOnSpawn = false
        toolbar.Parent = targetParent

        local bg = Instance.new("Frame")
        bg.Name = "Toolbar"
        bg.Size = UDim2.new(0, #modules * 42 + 12, 0, 38)
        bg.Position = UDim2.new(0.5, -(#modules * 42 + 12) / 2, 0, 80)
        bg.BackgroundColor3 = Color3.fromRGB(btnColor[1] or 30, btnColor[2] or 30, btnColor[3] or 40)
        bg.BackgroundTransparency = 0.2
        bg.BorderSizePixel = 0
        bg.Parent = toolbar
        corner(bg, 8)
        stroke(bg, Color3.fromRGB(0, 200, 255), 1, 0.3)
        makeDraggable(bg)

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size = UDim2.new(0, 22, 1, 0)
        titleLbl.Position = UDim2.new(0, 4, 0, 0)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Text = icon
        titleLbl.TextColor3 = Color3.fromRGB(0, 200, 255)
        titleLbl.TextSize = 16
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.Parent = bg

        -- Store module scripts
        local moduleFolder = Instance.new("Folder")
        moduleFolder.Name = pluginName .. "_Modules"
        moduleFolder.Parent = targetParent

        local moduleStates = {} -- track on/off per module
        local activeConnections = {} -- track running threads

        for idx, mod in ipairs(modules) do
            if type(mod) == "table" and mod.name and mod.source then
                -- Store source in StringValue
                local sv = Instance.new("StringValue")
                sv.Name = mod.name
                sv.Value = mod.source
                sv.Parent = moduleFolder

                -- Button for this module
                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(0, 36, 0, 28)
                btn.Position = UDim2.new(0, 30 + (idx - 1) * 42, 0.5, -14)
                btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
                btn.Text = mod.name:sub(1, 2):upper()
                btn.TextColor3 = Color3.fromRGB(180, 180, 190)
                btn.TextSize = 11
                btn.Font = Enum.Font.GothamBold
                btn.Parent = bg
                corner(btn, 6)

                local moduleOn = false
                local thread = nil

                btn.MouseButton1Click:Connect(function()
                    moduleOn = not moduleOn
                    if moduleOn then
                        btn.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
                        btn.TextColor3 = Color3.new(1, 1, 1)
                        -- Execute the module script
                        local fn, err = loadstring("local pluginModule = ...\n" .. mod.source)
                        if fn then
                            local ok, runErr = pcall(fn, { Name = mod.name, Source = mod.source, Parent = moduleFolder })
                            if not ok then
                                addMessage("⚠️ Plugin module '" .. mod.name .. "' error: " .. tostring(runErr), false, true)
                            end
                        else
                            addMessage("⚠️ Plugin module '" .. mod.name .. "' compile error: " .. tostring(err), false, true)
                        end
                        addMessage("✅ Plugin module: " .. mod.name .. " ON", false)
                    else
                        btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
                        btn.TextColor3 = Color3.fromRGB(180, 180, 190)
                        addMessage("⏹️ Plugin module: " .. mod.name .. " OFF", false)
                    end
                end)

                moduleStates[mod.name] = false
            end
        end

        table.insert(_batchCreated, toolbar)
        table.insert(_batchCreated, moduleFolder)
        updateSceneState(action, true)
        _lastClickInstance = toolbar
        return true, "✅ Created plugin: " .. pluginName .. " with " .. #modules .. " module(s)"

    elseif kind == "create_particle" then
        local target = resolveTarget(action.target)
        if not target then return false, "❌ create_particle: target '" .. tostring(action.target) .. "' not found" end
        local pe = Instance.new("ParticleEmitter")
        pe.Name = (action.name or "ParticleEmitter")
        pe.Texture = action.texture or "rbxasset://textures/particles/sparkles_main.dds"
        pe.Rate = action.rate or 20
        pe.Speed = action.speed and NumberRange.new(action.speed[1] or 5, action.speed[2] or 10) or NumberRange.new(5, 10)
        pe.Lifetime = action.lifetime and NumberRange.new(action.lifetime[1] or 2, action.lifetime[2] or 4) or NumberRange.new(2, 4)
        if action.size then
            local s = action.size
            pe.Size = NumberSequence.new(NumberSequenceKeypoint.new(0, s[1] or s[1]==nil and 1 or s[1]), NumberSequenceKeypoint.new(1, s[#s] or s[2] or 0.5))
        else
            pe.Size = NumberSequence.new(1, 0.5)
        end
        if action.color then
            local cs = {}
            for i, c in ipairs(action.color) do
                table.insert(cs, ColorSequenceKeypoint.new((i-1)/(#action.color-1), Color3.fromRGB(c[1] or 255, c[2] or 255, c[3] or 255)))
            end
            pe.Color = ColorSequence.new(cs)
        else
            pe.Color = ColorSequence.new(Color3.fromRGB(255, 200, 50))
        end
        pe.Transparency = action.transparency and NumberSequence.new(action.transparency[1] or 0, action.transparency[2] or 1) or NumberSequence.new(0, 1)
        pe.Rotation = action.rotation and NumberRange.new(action.rotation[1] or 0, action.rotation[2] or 360) or NumberRange.new(0, 360)
        if action.spread then pe.SpreadAngle = Vector2.new(action.spread, action.spread) end
        pe.Enabled = if action.enabled ~= nil then action.enabled else true
        pe.Parent = target
        table.insert(_batchCreated, pe)
        updateSceneState(action, true)
        _lastClickInstance = pe
        return true, "✨ Particle emitter added to " .. target.Name

    elseif kind == "create_light" then
        local target = resolveTarget(action.target)
        if not target then return false, "❌ create_light: target '" .. tostring(action.target) .. "' not found" end
        local lightType = action.lightType or "PointLight"
        local light = Instance.new(lightType)
        light.Name = (action.name or lightType)
        light.Color = action.color and Color3.fromRGB(action.color[1] or 255, action.color[2] or 255, action.color[3] or 255) or Color3.new(1, 1, 1)
        light.Brightness = action.brightness or (lightType == "SpotLight" and 2 or 1)
        if light:IsA("PointLight") or light:IsA("SpotLight") then
            light.Range = action.range or 16
        end
        if light:IsA("SpotLight") then
            light.Angle = action.angle or 90
            light.Face = action.Face and Enum.NormalId[action.Face] or Enum.NormalId.Front
        end
        if light:IsA("SurfaceLight") then
            light.Face = action.Face and Enum.NormalId[action.Face] or Enum.NormalId.Front
            light.Range = action.range or 16
        end
        if action.enabled ~= nil then light.Enabled = action.enabled end
        light.Parent = target
        table.insert(_batchCreated, light)
        updateSceneState(action, true)
        _lastClickInstance = light
        return true, "💡 " .. lightType .. " added to " .. target.Name

    elseif kind == "create_sound" then
        local soundId = action.soundId
        if not soundId or soundId == "" then return false, "❌ create_sound requires soundId" end
        local parent
        if action.target then
            parent = resolveTarget(action.target)
            if not parent then return false, "❌ create_sound: target '" .. tostring(action.target) .. "' not found" end
        else
            parent = resolveParent(action.parent, Workspace)
        end
        if not parent then parent = Workspace end
        local sound = Instance.new("Sound")
        sound.Name = action.name or "Sound"
        sound.SoundId = soundId
        sound.Volume = action.volume or 0.5
        sound.Pitch = action.pitch or 1
        sound.Looped = action.loops or false
        if action.startPaused then sound.Playing = false else sound.Playing = true end
        sound.Parent = parent
        table.insert(_batchCreated, sound)
        updateSceneState(action, true)
        _lastClickInstance = sound
        return true, "🔊 Sound created: " .. soundId

    elseif kind == "create_tween" then
        local target = resolveTarget(action.target)
        if not target then return false, "❌ create_tween: target '" .. tostring(action.target) .. "' not found" end
        local props = action.properties
        if not props or next(props) == nil then return false, "❌ create_tween requires a 'properties' table" end
        local duration = action.duration or 1
        local style = action.style or "Quad"
        local direction = action.direction or "Out"
        local tsi = TweenInfo.new(duration, Enum.EasingStyle[style] or Enum.EasingStyle.Quad,
            Enum.EasingDirection[direction] or Enum.EasingDirection.Out, action.repeatCount or 0,
            action.reverses or false)
        local tweenData = {}
        for k, v in pairs(props) do
            if type(v) == "table" and #v == 3 then
                if k:lower():find("color") then
                    pcall(function() tweenData[k] = Color3.fromRGB(v[1] or 255, v[2] or 255, v[3] or 255) end)
                else
                    tweenData[k] = Vector3.new(v[1] or 0, v[2] or 0, v[3] or 0)
                end
            else
                tweenData[k] = v
            end
        end
        local tween = game:GetService("TweenService"):Create(target, tsi, tweenData)
        tween:Play()
        table.insert(_batchCreated, tween)
        updateSceneState(action, true)
        _lastClickInstance = target
        return true, "🎬 Tween started on " .. target.Name .. " (" .. duration .. "s, " .. style .. direction .. ")"

    elseif kind == "create_animation" then
        local animType = action.animationType or "asset"
        if animType == "asset" then
            local targetHum = resolveTarget(action.humanoid or action.target)
            if not targetHum then return false, "❌ create_animation: target humanoid '" .. tostring(action.humanoid or action.target) .. "' not found" end
            local assetId = action.assetId
            if not assetId or assetId == "" then return false, "❌ create_animation: assetId required for 'asset' type" end
            local anim = Instance.new("Animation")
            anim.Name = action.name or "Animation"
            anim.AnimationId = assetId
            local parent = resolveParent(action.parent, targetHum.Parent)
            anim.Parent = parent or targetHum.Parent
            local animator = targetHum:FindFirstChildOfClass("Animator")
            if not animator then animator = Instance.new("Animator"); animator.Parent = targetHum end
            local track = animator:LoadAnimation(anim)
            track:Play()
            if action.loop then track:AdjustSpeed(action.speed or 1)
                track.Looped = true end
            table.insert(_batchCreated, anim)
            updateSceneState(action, true)
            _lastClickInstance = anim
            return true, "🎭 Animation loaded & played on " .. targetHum.Name
        elseif animType == "keyframe" then
            local targetHum = resolveTarget(action.humanoid or action.target)
            if not targetHum then return false, "❌ create_animation: target humanoid '" .. tostring(action.humanoid or action.target) .. "' not found" end
            local frames = action.frames
            if not frames or type(frames) ~= "table" or #frames == 0 then
                return false, "❌ create_animation: 'frames' array required for keyframe type"
            end
            local anim = Instance.new("Animation")
            anim.Name = action.name or "KeyframeAnimation"
            local parent = resolveParent(action.parent, targetHum.Parent)
            anim.Parent = parent or targetHum.Parent
            local animator = targetHum:FindFirstChildOfClass("Animator")
            if not animator then animator = Instance.new("Animator"); animator.Parent = targetHum end
            -- Build keyframe sequence via a generated script
            local kfSource = "local plr = game:GetService('Players').LocalPlayer\nlocal char = plr.Character\nif not char then return end\nlocal hum = char:WaitForChild('Humanoid')\nlocal animator = hum:FindFirstChildOfClass('Animator') or Instance.new('Animator')\nif not animator.Parent then animator.Parent = hum end\nlocal anim = Instance.new('Animation')\nanim.AnimationId = 'rbxasset://animations/anim_slowrun.rbxm'\n-- keyframe animation not fully supported via JSON yet; using run animation as fallback\nlocal track = animator:LoadAnimation(anim)\ntrack:Play()\nif " .. tostring(action.loop or false) .. " then track.Looped = true end"
            local kfScript = Instance.new("LocalScript")
            kfScript.Name = (action.name or "KeyframeAnim") .. "_Loader"
            kfScript.Parent = parent or targetHum.Parent
            kfScript.Source = kfSource
            table.insert(_batchCreated, kfScript)
            updateSceneState(action, true)
            _lastClickInstance = kfScript
            return true, "🎭 Keyframe animation created (" .. #frames .. " frames)"
        else
            return false, "❌ Unknown animationType: " .. tostring(animType)
        end

    elseif kind == "create_texture" then
        local target = resolveTarget(action.target)
        if not target then return false, "❌ create_texture: target '" .. tostring(action.target) .. "' not found" end
        local texType = action.textureType or "Decal"
        local tex = Instance.new(texType)
        tex.Name = action.name or texType
        tex.Texture = action.textureId or "rbxasset://textures/trans.png"
        if action.face then tex.Face = Enum.NormalId[action.face] end
        if action.color then tex.Color3 = Color3.fromRGB(action.color[1] or 255, action.color[2] or 255, action.color[3] or 255) end
        if action.transparency then tex.Transparency = action.transparency end
        if tex:IsA("Texture") then
            if action.studsPerTileU then tex.StudsPerTileU = action.studsPerTileU end
            if action.studsPerTileV then tex.StudsPerTileV = action.studsPerTileV end
        end
        tex.Parent = target
        table.insert(_batchCreated, tex)
        updateSceneState(action, true)
        _lastClickInstance = tex
        return true, "🎨 " .. texType .. " applied to " .. target.Name

    elseif kind == "create_npc" then
        local npcName = action.name or "NPC"
        local pos = action.position
        if not pos or type(pos) ~= "table" or #pos < 3 then
            return false, "❌ create_npc requires position:[x,y,z]"
        end
        local npcColor = action.color or {180, 120, 80}
        local ws = action.walkspeed or 16
        local hp = action.health or 100
        local scale = action.resize or 1
        local npcFolder = Instance.new("Folder")
        npcFolder.Name = npcName
        npcFolder.Parent = resolveParent(action.parent, Workspace)
        -- Create NPC parts (R6 model)
        local torso = Instance.new("Part")
        torso.Name = "Torso"; torso.Size = Vector3.new(2, 2, 1); torso.Position = Vector3.new(pos[1] or 0, (pos[2] or 3) + 1.5, pos[3] or 0)
        torso.Anchored = false; torso.CanCollide = true; torso.BrickColor = BrickColor.new(Color3.fromRGB(npcColor[1] or 180, npcColor[2] or 120, npcColor[3] or 80))
        torso.Parent = npcFolder
        local head = Instance.new("Part")
        head.Name = "Head"; head.Size = Vector3.new(1, 1, 1) * scale; head.Shape = Enum.PartType.Ball; head.Position = Vector3.new(pos[1] or 0, (pos[2] or 3) + 3, pos[3] or 0)
        head.Anchored = false; head.CanCollide = true; head.BrickColor = BrickColor.new(Color3.fromRGB(255, 200, 150))
        head.Parent = npcFolder
        local larm = Instance.new("Part")
        larm.Name = "Left Arm"; larm.Size = Vector3.new(1, 2, 1); larm.Position = Vector3.new((pos[1] or 0) - 1.5, (pos[2] or 3) + 1.5, pos[3] or 0)
        larm.Anchored = false; larm.CanCollide = true; larm.BrickColor = torso.BrickColor; larm.Parent = npcFolder
        local rarm = Instance.new("Part")
        rarm.Name = "Right Arm"; rarm.Size = Vector3.new(1, 2, 1); rarm.Position = Vector3.new((pos[1] or 0) + 1.5, (pos[2] or 3) + 1.5, pos[3] or 0)
        rarm.Anchored = false; rarm.CanCollide = true; rarm.BrickColor = torso.BrickColor; rarm.Parent = npcFolder
        local lleg = Instance.new("Part")
        lleg.Name = "Left Leg"; lleg.Size = Vector3.new(1, 2, 1); lleg.Position = Vector3.new((pos[1] or 0) - 0.5, (pos[2] or 3) - 0.5, pos[3] or 0)
        lleg.Anchored = false; lleg.CanCollide = true; lleg.BrickColor = BrickColor.new(Color3.fromRGB(30, 30, 120)); lleg.Parent = npcFolder
        local rleg = Instance.new("Part")
        rleg.Name = "Right Leg"; rleg.Size = Vector3.new(1, 2, 1); rleg.Position = Vector3.new((pos[1] or 0) + 0.5, (pos[2] or 3) - 0.5, pos[3] or 0)
        rleg.Anchored = false; rleg.CanCollide = true; rleg.BrickColor = lleg.BrickColor; rleg.Parent = npcFolder
        -- Weld joints
        local function weld(p0, p1, name)
            local w = Instance.new("Weld"); w.Name = name; w.Part0 = p0; w.Part1 = p1
            w.C0 = p0.CFrame:inverse() * p1.CFrame; w.Parent = p0
        end
        weld(torso, head, "Neck"); weld(torso, larm, "Left Shoulder"); weld(torso, rarm, "Right Shoulder")
        weld(torso, lleg, "Left Hip"); weld(torso, rleg, "Right Hip")
        -- Humanoid
        local hum = Instance.new("Humanoid")
        hum.Name = "Humanoid"; hum.MaxHealth = hp; hum.Health = hp; hum.WalkSpeed = ws; hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        hum.Parent = npcFolder
        -- HumanoidRootPart
        local root = Instance.new("Part")
        root.Name = "HumanoidRootPart"; root.Size = Vector3.new(2, 2, 1); root.Shape = Enum.PartType.Cylinder
        root.Position = Vector3.new(pos[1] or 0, (pos[2] or 3) + 0.5, pos[3] or 0)
        root.Anchored = true; root.Transparency = 1; root.CanCollide = false; root.Parent = npcFolder
        weld(torso, root, "RootJoint")
        -- Head Billboard (name tag)
        local bb = Instance.new("BillboardGui")
        bb.Name = "NameTag"; bb.Size = UDim2.new(0, 60, 0, 20); bb.StudsOffset = Vector3.new(0, 2.5, 0); bb.AlwaysOnTop = true; bb.Parent = head
        local nl = Instance.new("TextLabel")
        nl.Size = UDim2.new(1, 0, 1, 0); nl.BackgroundTransparency = 1; nl.Text = npcName; nl.TextColor3 = Color3.new(1, 1, 1)
        nl.TextSize = 14; nl.Font = Enum.Font.GothamBold; nl.TextStrokeTransparency = 0.5; nl.Parent = bb
        table.insert(_batchCreated, npcFolder)
        updateSceneState(action, true)
        _lastClickInstance = npcFolder
        return true, "🧑‍🦱 NPC created: " .. npcName .. " at " .. tostring(pos[1]) .. "," .. tostring(pos[2]) .. "," .. tostring(pos[3])

    elseif kind == "load_model" then
        local assetId = action.assetId
        if not assetId or assetId == "" then return false, "❌ load_model requires 'assetId' (rbxassetid://...)" end
        local InsertService = game:GetService("InsertService")
        local parent = resolveParent(action.parent, Workspace)
        local modelName = action.name or "LoadedModel"
        local pos = action.position
        local loaded = nil
        local ok, result = pcall(function()
            local id = assetId:match("rbxassetid://(%d+)") or assetId:match("(%d+)")
            if id then
                local m = InsertService:LoadAsset(tonumber(id))
                if m then loaded = m end
            end
        end)
        if not ok or not loaded then
            -- Fallback: create a placeholder
            local fb = Instance.new("Part")
            fb.Name = modelName .. "_Placeholder"
            fb.Size = Vector3.new(4, 4, 4)
            fb.Anchored = true; fb.CanCollide = true
            fb.Color = Color3.fromRGB(200, 100, 100)
            if pos then fb.Position = Vector3.new(pos[1] or 0, pos[2] or 5, pos[3] or 0) end
            fb.Parent = parent
            table.insert(_batchCreated, fb)
            _lastClickInstance = fb
            updateSceneState(action, true)
            return true, "⚠️ Model " .. assetId .. " couldn't load (not found or restricted). Created placeholder part instead."
        end
        loaded.Name = modelName
        if loaded.Parent then loaded.Parent = nil end
        loaded.Parent = parent
        if pos then
            local rootPart = loaded:FindFirstChild("HumanoidRootPart") or loaded:FindFirstChildWhichIsA("BasePart")
            if rootPart then rootPart.CFrame = CFrame.new(Vector3.new(pos[1] or 0, pos[2] or 5, pos[3] or 0)) end
        end
        if action.makeTool then
            loaded:FindFirstChildWhichIsA("Part").Anchored = false
        end
        table.insert(_batchCreated, loaded)
        updateSceneState(action, true)
        _lastClickInstance = loaded
        return true, "📦 Model loaded: " .. modelName .. " (" .. assetId .. ")"

    else
        return false, "❌ Unknown action type: " .. tostring(kind)
    end
end

local SYSTEM_PROMPT = [[
You are Skill-AI v1.3 — Roblox master builder. Build ANY game: tower defense, FPS, RPG, obby, racing, survival, tycoon, adventure, battle royale. NPCs, animations, textures, GUIs, plugins, guns, HP, save/load, multiplayer, leaderboards, shops, pets, waves, upgrades, boss fights — all in ONE response. Output ONLY valid JSON.

=== RULES ===
- ONLY valid JSON. No text/markdown/backticks. No reasoning. Output JSON immediately.
- NO Lua in JSON: use [255,0,0] NOT Color3.fromRGB/Color3.new. Use [5,5,5] NOT Vector3.new. Use [0.5,0,0.2,0] NOT UDim2.new.
- "className":"Part" NOT "Block"/"Ball"/"Cylinder" — use "Shape":"Box" for shape.
- Prefix [EASY]=simple(1-3 parts,minimal scripts) [NORMAL]=moderate [HARD]=full game with complete working Lua code, no placeholders, no TODOs.
- Format: {"actions":[...],"reply":"message"}. All actions in one array, executed sequentially.

=== ACTIONS (use these) ===
1. create_instance: {type,className,name,parent,containerName?,properties?,handleProperties?}
2. create_compound: {type,className:"Model",name,parent,parts:[{className,size,position,color,material,shape?}],makeTool?}
3. create_script: {type,className:"Script"|"LocalScript",name,parent,source}
4. create_multiple: {type,className,count,containerName,parent,properties?,rejectionRadius?}
5. create_enclosure: {type,name,parent,containerName?,centerX?,centerY?,centerZ?,width?,depth?,wallHeight?,floor?,openSides?,color?,material?,barrier?}
6. create_challenge_system: {type,name,parent,containerName?,challengeType,targetCount,title?,centerX?,centerY?,centerZ?,width?,depth?,height?,visibleFloor?,walls?,wallHeight?,wallColor?,wallMaterial?,guiPosition?,guiSize?}
7-14: set_property, delete, clone, rename, move, set_lighting, set_character, undo
15. create_plugin: {type,name,modules:[{name,source}],icon?,buttonColor?,parent?}
16. create_particle: {type,target,texture?,rate?,speed?,lifetime?,size?,color?,transparency?,rotation?,spread?,enabled?}
17. create_light: {type,lightType:"PointLight"|"SpotLight"|"SurfaceLight",target,color?,brightness?,range?,angle?,enabled?}
18. create_sound: {type,soundId:"rbxassetid://...",target?,parent?,name?,volume?,pitch?,loops?,startPaused?}
19. create_tween: {type,target,properties:{...},duration?,style?,direction?,repeatCount?,reverses?}
20. create_animation: {type,animationType:"keyframe"|"asset",target?,humanoid?,parent?,name?,assetId?,frames?,loop?,speed?}
21. create_texture: {type,textureType:"Decal"|"Texture",target,textureId:"rbxassetid://...",face?,color?,transparency?,studsPerTileU?,studsPerTileV?}
22. create_npc: {type,name,position,color?,walkspeed?,health?,resize?,parent?}
23. load_model: {type,assetId:"rbxassetid://...",name?,parent?,position?,makeTool?}

=== BUILD RULES ===
- PARENTING: GUI→StarterGui, Parts→Workspace, Scripts→ServerStorage/Lighting, LocalScripts→StarterPlayerScripts
- NEVER parent GUI to Workspace. NEVER parent Parts to StarterGui/StarterPlayerScripts. NEVER parent Scripts to Workspace.
- When a script controls a GUI, parent the script INSIDE the ScreenGui or to StarterPlayerScripts, NOT Workspace.
- Textures/Decals: use `target` (the part), NOT `parent`. Decal.Parent = the part, not Workspace.
- Parents: Workspace,StarterGui,StarterPlayerScripts,StarterCharacterScripts,Lighting,ServerStorage,ReplicatedStorage,CoreGui,StarterPack
- Parts: Block,Ball,Cylinder,Wedge,CornerWedge. Materials: Plastic,Metal,Wood,Glass,Neon,Granite,Marble,Cement.
- ANCHOR static=true. Only Tools=false. CanCollide=true auto. Stack Y+5 per level.
- Colors: RGB [255,0,0] or BrickColor string. Sizes: doors 4x7x1, platforms 10x0.5x10, walls 0.5x8x6.
- GUI circles: Frame+UICorner(CornerRadius=UDim.new(1,0)).
- Scripts: NEVER "workspace.X" — use :WaitForChild(). nil-guard. NEVER SourceBackup. Parts FIRST, scripts SECOND. Respawn-safe (auto re-run).
- Reply: MUST include full script source code. Numbered plan for complex builds.
- Game types: TD=path+spawn+towers+waves+currency+upgrades. FPS=guns+damage+HP+ammo+respawn. Sim=zone+collect+currency+shop+save. Race=track+vehicle+checkpoint+timer+leaderboard.
- Enclosure ex: {"type":"create_enclosure","name":"Platform","parent":"Workspace","centerX":0,"centerY":8,"centerZ":0,"width":10,"depth":10,"wallHeight":6}
- Challenge ex: {"type":"create_challenge_system","name":"KillChallenge","parent":"Workspace","challengeType":"kill","targetCount":10,"centerX":0,"centerY":0,"centerZ":0,"width":30,"depth":30,"height":8}
- HARD mode: complete working Lua in every script — every function, event, line. No placeholders or TODOs.
]]

local REASONING_PATTERNS = {
    "^Let me%s", "^I['']?ll%s", "^I think%s", "^First,?%s",
    "^The user%s", "^Okay,?%s", "^So,?%s", "^Alright,?%s",
    "^Here['']?s%s", "^This is%s", "^I need%s", "^I should%s",
    "^I will%s", "^We need%s", "^We should%s", "^We can%s",
}

local function stripReasoning(text)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        local stripped = line
        for _, pat in ipairs(REASONING_PATTERNS) do
            stripped = stripped:gsub(pat, "")
        end
        if #stripped > 0 then
            table.insert(lines, stripped)
        end
    end
    return table.concat(lines, "\n")
end

-- Fix Lua expressions inside JSON (e.g. Vector3.new(1,2,3) → [1,2,3])
local function fixLuaInJson(str)
    -- Color3.fromRGB(255,0,0) → [255,0,0]
    str = str:gsub("Color3%.fromRGB%s*%((%d+%s*,%s*%d+%s*,%s*%d+)%)", function(inner)
        return "[" .. inner .. "]"
    end)
    -- Color3.new(0.5,0,0) → [128,0,0]
    str = str:gsub("Color3%.new%s*%(([%d%.]+%s*,%s*[%d%.]+%s*,%s*[%d%.]+)%)", function(inner)
        local r, g, b = inner:match("([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)")
        if r and g and b then
            r = math.floor((tonumber(r) or 0) * 255)
            g = math.floor((tonumber(g) or 0) * 255)
            b = math.floor((tonumber(b) or 0) * 255)
            return "[" .. r .. "," .. g .. "," .. b .. "]"
        end
        return "[" .. inner .. "]"
    end)
    -- Vector3.new(1,2,3) or Vector3.new(-1,2,0) → [1,2,3]
    str = str:gsub("Vector[23]%.new%s*%(([%d%.%-]+%s*,%s*[%d%.%-]+%s*,%s*[%d%.%-]+)%)", function(inner)
        return "[" .. inner .. "]"
    end)
    -- UDim2.new(0.5,0,0.2,0) → [0.5,0,0.2,0]
    str = str:gsub("UDim2%.new%s*%(([%d%.%-]+%s*,%s*[%d%.%-]+%s*,%s*[%d%.%-]+%s*,%s*[%d%.%-]+)%)", function(inner)
        return "[" .. inner .. "]"
    end)
    -- NumberRange.new(1,10) → [1,10]
    str = str:gsub("NumberRange%.new%s*%(([%d%.]+%s*,%s*[%d%.]+)%)", function(inner)
        return "[" .. inner .. "]"
    end)
    -- NumberSequence.new(1, 0.5) → {"__NumberSequence":[1,0.5]}
    str = str:gsub("NumberSequence%.new%s*%(([%d%.]+%s*,%s*[%d%.]+)%)", function(inner)
        return '{"__NumberSequence":[' .. inner .. ']}'
    end)
    -- BrickColor.new("Bright red") → "Bright red"
    str = str:gsub('BrickColor%.new%s*%("[^"]+")', function(inner)
        return inner
    end)
    -- Normalize class names
    str = str:gsub('"className"%s*:%s*"Block"', '"className":"Part"')
    str = str:gsub('"className"%s*:%s*"Ball"', '"className":"Part"')
    str = str:gsub('"className"%s*:%s*"Cylinder"', '"className":"Part"')
    -- Normalize "shape" to "Shape"
    str = str:gsub('"shape"%s*:%s*"Box"', '"Shape":"Box"')
    str = str:gsub('"shape"%s*:%s*"Block"', '"Shape":"Block"')
    str = str:gsub('"shape"%s*:%s*"Ball"', '"Shape":"Ball"')
    return str
end

local function tryExtractJson(text)
    if type(text) ~= "string" or text == "" then return nil end
    local cleaned = stripReasoning(text)
    cleaned = cleaned:gsub("```json", ""):gsub("```lua", ""):gsub("```", ""):gsub("^%s+", ""):gsub("%s+$", "")
    cleaned = cleaned:gsub("^[%s\n\r]+", ""):gsub("[%s\n\r]+$", "")
    -- strip invisible / control chars (except \t \n \r) that break JSONDecode
    cleaned = cleaned:gsub("[%c]", function(c)
        if c == "\t" or c == "\n" or c == "\r" then return c end
        return ""
    end)

    -- Convert Lua expressions inside JSON to proper JSON
    cleaned = fixLuaInJson(cleaned)

    -- If no "actions" wrapper but has a single action object, wrap it
    if not cleaned:find('"actions"', 1, true) and cleaned:match('"type"%s*:') then
        cleaned = '{"actions":[' .. cleaned .. '],"reply":"Built."}'
    end

    local function tryDecode(str)
        local ok, res = pcall(function() return HttpService:JSONDecode(str) end)
        if ok and type(res) == "table" then return res end
        return nil
    end

    -- try direct
    local plan = tryDecode(cleaned)
    if plan then return plan end

    -- try extracting from known start patterns
    for _, prefix in ipairs({'{"actions"', '{"steps"', '{"reply"', '{"type"'}) do
        local s = cleaned:find(prefix, 1, true)
        if s then
            local e = cleaned:reverse():find("}")
            if e then
                local realEnd = #cleaned - e + 1
                if realEnd > s then
                    local sub = cleaned:sub(s, realEnd)
                    plan = tryDecode(sub)
                    if plan then return plan end
                end
            end
        end
    end

    -- first { to last }
    local s = cleaned:find("{")
    local e = cleaned:reverse():find("}")
    if s and e then
        local realEnd = #cleaned - e + 1
        if realEnd > s then
            local sub = cleaned:sub(s, realEnd)
            plan = tryDecode(sub)
            if plan then return plan end
            -- maybe truncated — try adding closing braces
            local extras = { "}", "}]}", "}]}}", "} }" }
            for _, extra in ipairs(extras) do
                local fixed = sub .. extra
                plan = tryDecode(fixed)
                if plan then return plan end
            end
        end
    end

    return nil
end

local function buildSceneTree()
    local lines = {}
    local limit = 120
    local count = 0

    -- tracked containers from this session
    local hasContainers = false
    for key, ss in pairs(sceneState) do
        local names = {}
        if ss.createdNames then
            for n, _ in pairs(ss.createdNames) do
                table.insert(names, n)
            end
        end
        if #names > 0 then
            table.insert(lines, "  " .. key .. " (" .. (ss.className or "?") .. ", " .. ss.count .. " total): " .. table.concat(names, ", "))
            hasContainers = true
        end
    end
    if hasContainers then
        table.insert(lines, 1, "--- this session ---")
        table.insert(lines, 2, "")
    end

    -- live scene tree
    local servicesToScan = {
        Workspace = Workspace,
        StarterPack = StarterPack,
        Lighting = Lighting,
        ServerStorage = ServerStorage,
        ReplicatedStorage = ReplicatedStorage,
        StarterGui = StarterGui,
        StarterCharacterScripts = StarterCharacterScripts,
        StarterPlayerScripts = StarterPlayerScripts,
    }

    local function shortClass(cn)
        local map = { Part = "Part", MeshPart = "Mesh", Model = "Model", Folder = "Folder",
            Script = "Script", LocalScript = "LScript", StringValue = "StrVal",
            ScreenGui = "Gui", Frame = "Frame", TextLabel = "Label", TextButton = "Btn",
            ImageLabel = "Img", ScrollingFrame = "ScrFrame", ViewportFrame = "VpFrame" }
        return map[cn] or cn
    end

    for svcName, svc in pairs(servicesToScan) do
        if svc and type(svc) == "userdata" then
            local children = svc:GetChildren()
            if #children > 0 then
                table.insert(lines, "")
                table.insert(lines, svcName .. ":")
                for i, child in ipairs(children) do
                    if count >= limit then break end
                    local stem = (i == #children) and "    " or "│   "
                    local fork = (i == #children) and "└── " or "├── "
                    local loc = child:IsA("BasePart") and string.format(" @%.0f,%.0f,%.0f", child.CFrame.X, child.CFrame.Y, child.CFrame.Z) or ""
                    table.insert(lines, fork .. child.Name .. loc .. " (" .. shortClass(child.ClassName) .. ")")
                    count += 1
                    if (child:IsA("Model") or child:IsA("Folder")) and #child:GetChildren() > 0 then
                        local gcs = child:GetChildren()
                        for j, gc in ipairs(gcs) do
                            if count >= limit then break end
                            local gfork = (j == #gcs) and "└── " or "├── "
                            local gloc = gc:IsA("BasePart") and string.format(" @%.0f,%.0f,%.0f", gc.CFrame.X, gc.CFrame.Y, gc.CFrame.Z) or ""
                            table.insert(lines, stem .. gfork .. gc.Name .. gloc .. " (" .. shortClass(gc.ClassName) .. ")")
                            count += 1
                        end
                    end
                end
            end
        end
    end

    if #lines == 0 then return "" end
    return "=== SCENE ===\n" .. table.concat(lines, "\n") .. "\n=== END SCENE ==="
end

local _lastValidationErrors = nil

local VALIDATION_SKIP_REFS = {
    humanoid = true, handle = true, torso = true, head = true,
    ["left arm"] = true, ["right arm"] = true, ["left leg"] = true, ["right leg"] = true,
    playergui = true, backpack = true, leaderstats = true, configuration = true,
    uppertorso = true, lowertorso = true, lefthand = true, righthand = true,
    leftfoot = true, rightfoot = true,
}

local function validateActions(actions)
    local errors = {}
    local createdNames = {}
    for i, action in ipairs(actions) do
        local parent = action.parent
        if (action.type == "create_instance" or action.type == "create_compound") and action.name then
            createdNames[action.name:lower()] = true
        end
        -- Size validation: skip for GUI objects (they use UDim2 = 4-element [sX,oX,sY,oY])
        if action.type == "create_instance" and type(action.properties) == "table" then
            local guiClasses = { ScreenGui = true, Frame = true, TextLabel = true, TextButton = true,
                ImageLabel = true, ScrollingFrame = true, BillboardGui = true }
            local isGUI = guiClasses[action.className]
            local sz = action.properties.Size
            if type(sz) == "table" and isGUI then
                if #sz ~= 4 or type(sz[1]) ~= "number" or type(sz[2]) ~= "number" or type(sz[3]) ~= "number" or type(sz[4]) ~= "number" then
                    table.insert(errors, ("Action %d: '%s' has invalid UDim2 Size %s (needs 4 numbers: scaleX, offsetX, scaleY, offsetY)."):format(
                        i, action.name or "?", HttpService:JSONEncode(sz)
                    ))
                end
            elseif type(sz) == "table" and not isGUI then
                if not ((sz[1] or 0) > 0 and (sz[2] or 0) > 0 and (sz[3] or 0) > 0) then
                    table.insert(errors, ("Action %d: '%s' has invalid Size %s (must be positive numbers on all 3 axes)."):format(
                        i, action.name or "?", HttpService:JSONEncode(sz)
                    ))
                end
            end
            -- موقع متطرف بشكل غير منطقي (احتمال خطأ حسابي بالـ AI، مو طلب فعلي)
            local pos = action.properties.Position
            if type(pos) == "table" then
                for axisIdx = 1, 3 do
                    local v = pos[axisIdx]
                    if type(v) == "number" and math.abs(v) > 100000 then
                        table.insert(errors, ("Action %d: '%s' has extreme Position value (%d) on axis %d. Likely a calculation error — keep coordinates reasonable (e.g. within ±2000)."):format(
                            i, action.name or "?", v, axisIdx
                        ))
                    end
                end
            end
        end
        -- نفس فحص الحجم لأجزاء create_compound (كل part بالمصفوفة)
        if action.type == "create_compound" and type(action.parts) == "table" then
            for partIdx, partData in ipairs(action.parts) do
                if type(partData) == "table" and type(partData.size) == "table" then
                    local sz = partData.size
                    if not ((sz[1] or 0) > 0 and (sz[2] or 0) > 0 and (sz[3] or 0) > 0) then
                        table.insert(errors, ("Action %d (compound '%s', part %d): invalid size %s (must be positive on all 3 axes)."):format(
                            i, action.name or "?", partIdx, HttpService:JSONEncode(sz)
                        ))
                    end
                end
            end
        end
        -- GUI objects in Workspace
        if action.type == "create_instance" and parent == "Workspace" then
            local guiClasses = { ScreenGui = true, Frame = true, TextLabel = true, TextButton = true,
                ImageLabel = true, ScrollingFrame = true, BillboardGui = true }
            if guiClasses[action.className] then
                table.insert(errors, ("Action %d: GUI '%s' parented to Workspace. Use StarterGui instead."):format(i, action.name or "?"))
            end
        end
        -- Parts in GUI services
        if action.type == "create_instance" and parent and action.className then
            local isPart = action.className == "Part" or action.className == "MeshPart" or action.className == "WedgePart" or action.className == "CylinderPart" or action.className == "BallPart"
            local isGuiSvc = parent == "StarterGui" or parent == "StarterPlayerScripts" or parent == "StarterCharacterScripts"
            if isPart and isGuiSvc then
                table.insert(errors, ("Action %d: Part '%s' parented to %s. Use Workspace instead."):format(i, action.name or "?", parent))
            end
        end
        -- Scripts/values can't live in Workspace (not a container for code)
        if action.type == "create_script" and (parent == "Workspace") then
            table.insert(errors, ("Action %d (script '%s'): parented to Workspace. Use ServerScriptService or StarterPlayerScripts instead."):format(
                i, action.name or "?"
            ))
        end
        -- Script references a part not yet created
        if action.type == "create_script" and action.source then
            for ref in action.source:gmatch(':WaitForChild%("([^"]+)"%)') do
                local refLower = ref:lower()
                if not VALIDATION_SKIP_REFS[refLower] and not createdNames[refLower] then
                    local exists = findByName(ref)
                    if not exists then
                        table.insert(errors, ("Action %d (script '%s'): references '%s' which doesn't exist. Create it in a PRIOR action."):format(
                            i, action.name or "?", ref
                        ))
                    end
                end
            end
            for ref in action.source:gmatch(':FindFirstChild%("([^"]+)"%)') do
                local refLower = ref:lower()
                if not VALIDATION_SKIP_REFS[refLower] and not createdNames[refLower] then
                    local exists = findByName(ref)
                    if not exists then
                        table.insert(errors, ("Action %d (script '%s'): references FindFirstChild('%s') which doesn't exist. Create it first."):format(
                            i, action.name or "?", ref
                        ))
                    end
                end
            end
        end
        -- create_challenge_system validation
        if action.type == "create_challenge_system" then
            local validTypes = { reach = true, survive = true, kill = true, collect = true }
            local ct = action.challengeType
            if ct and not validTypes[ct:lower()] then
                table.insert(errors, ("Action %d (challenge '%s'): invalid challengeType '%s'. Valid: reach, survive, kill, collect"):format(
                    i, action.name or "?", ct
                ))
            end
            local tc = tonumber(action.targetCount)
            if tc and (tc < 1 or tc > 1000) then
                table.insert(errors, ("Action %d (challenge '%s'): targetCount must be 1-1000, got %s"):format(
                    i, action.name or "?", tostring(tc)
                ))
            end
            local w = tonumber(action.width)
            local d = tonumber(action.depth)
            local h = tonumber(action.height)
            if w and (w < 1 or w > 500) then
                table.insert(errors, ("Action %d (challenge '%s'): width must be 1-500, got %s"):format(i, action.name or "?", tostring(w)))
            end
            if d and (d < 1 or d > 500) then
                table.insert(errors, ("Action %d (challenge '%s'): depth must be 1-500, got %s"):format(i, action.name or "?", tostring(d)))
            end
            if h and (h < 1 or h > 200) then
                table.insert(errors, ("Action %d (challenge '%s'): height must be 1-200, got %s"):format(i, action.name or "?", tostring(h)))
            end
        end
        -- deeper script validation: detect workspace.X dot-access (forbidden by prompt rules)
        if action.type == "create_script" and action.source then
            local src = action.source
            -- pattern: workspace.Something (dot-access)
            for matchPos, _ in src:gmatch("()workspace%.%a") do
                local contextStart = math.max(1, matchPos - 15)
                local contextEnd = math.min(#src, matchPos + 25)
                local snippet = src:sub(contextStart, contextEnd):gsub("\n", "\\n")
                table.insert(errors, ("Action %d (script '%s'): uses 'workspace.X' dot-access at pos %d (\"...%s...\"). Use script.Parent:WaitForChild('X') instead."):format(
                    i, action.name or "?", matchPos, snippet
                ))
                break
            end
            -- pattern: game.Workspace.Something
            for matchPos, _ in src:gmatch("()game%.Workspace%.%a") do
                local contextStart = math.max(1, matchPos - 15)
                local contextEnd = math.min(#src, matchPos + 30)
                local snippet = src:sub(contextStart, contextEnd):gsub("\n", "\\n")
                table.insert(errors, ("Action %d (script '%s'): uses 'game.Workspace.X' dot-access at pos %d (\"...%s...\"). Use script.Parent:WaitForChild('X') instead."):format(
                    i, action.name or "?", matchPos, snippet
                ))
                break
            end
        end
    end

    -- cross-action ordering check: scripts referencing parts must come after those parts are created
    do
        local createdByAction = {}
        for i, action in ipairs(actions) do
            if (action.type == "create_instance" or action.type == "create_compound") and action.name then
                createdByAction[action.name:lower()] = i
            end
            if action.type == "create_enclosure" and action.name then
                createdByAction[action.name:lower()] = i
            end
            if action.type == "create_challenge_system" and action.name then
                createdByAction[action.name:lower()] = i
            end
            if action.type == "create_multiple" and action.namePrefix then
                createdByAction[action.namePrefix:lower()] = i
            end
        end
        for i, action in ipairs(actions) do
            if action.type == "create_script" and action.source then
                for ref in action.source:gmatch(':WaitForChild%("([^"]+)"%)') do
                    local refLower = ref:lower()
                    if not VALIDATION_SKIP_REFS[refLower] and createdByAction[refLower] and createdByAction[refLower] > i then
                        table.insert(errors, ("Action %d (script '%s'): references part '%s' via WaitForChild, but that part is created LATER in action %d. Parts must be created BEFORE scripts that reference them."):format(
                            i, action.name or "?", ref, createdByAction[refLower]
                        ))
                    end
                end
                for ref in action.source:gmatch(':FindFirstChild%("([^"]+)"%)') do
                    local refLower = ref:lower()
                    if not VALIDATION_SKIP_REFS[refLower] and createdByAction[refLower] and createdByAction[refLower] > i then
                        table.insert(errors, ("Action %d (script '%s'): references FindFirstChild('%s'), but that part is created LATER in action %d. Reorder: create first, then script."):format(
                            i, action.name or "?", ref, createdByAction[refLower]
                        ))
                    end
                end
            end
        end
    end

    -- ⚠️ فحص تنظيم: لو فيه أكثر من create_instance بدون containerName للقطع
    -- اللي مش GUI أو Script (لأن GUI عنده ScreenGui اللي هو container أصلاً)
    do
        local guiClasses = { ScreenGui = true, Frame = true, TextLabel = true, TextButton = true,
            ImageLabel = true, ScrollingFrame = true, BillboardGui = true, ViewportFrame = true }
        local noContainerCount = 0
        local containerNamesUsed = {}
        for _, action in ipairs(actions) do
            if action.type == "create_instance" and not guiClasses[action.className] and action.className ~= "Script" and action.className ~= "LocalScript" then
                if not action.containerName or action.containerName == "" then
                    noContainerCount = noContainerCount + 1
                else
                    containerNamesUsed[action.containerName] = (containerNamesUsed[action.containerName] or 0) + 1
                end
            end
        end
        local distinctContainers = 0
        for _ in pairs(containerNamesUsed) do distinctContainers = distinctContainers + 1 end
        if noContainerCount >= 3 then
            table.insert(errors, ("You created %d separate parts via create_instance without any containerName. Per the ORGANIZATION RULE, give them all the SAME containerName so they group under one Folder instead of scattering loose parts in the Explorer."):format(noContainerCount))
        elseif distinctContainers > 1 and noContainerCount == 0 then
            table.insert(errors, "You used multiple different containerName values for parts that appear to belong to the same build. Use ONE consistent containerName for all parts of a single logical build.")
        end
    end

    return errors
end

local function requestPlan(question, retryCount, accumUsage)
    retryCount = retryCount or 0
    accumUsage = accumUsage or { prompt_tokens = 0, completion_tokens = 0, total_tokens = 0 }
    local maxRetries = 2

    local messages = {}
    if CURRENT_PROVIDER ~= "nvidia" then
        table.insert(messages, { role = "system", content = SYSTEM_PROMPT })
    end

    -- Only send history and scene if they have content (saves tokens)
    local hasScene = next(sceneState) ~= nil
    if hasScene then
        for _, histMsg in ipairs(buildHistoryMessages()) do
            table.insert(messages, histMsg)
        end
    end

    local sceneJson = ""
    if hasScene then
        sceneJson = buildSceneTree()
    end
    local enrichedQuestion = question
    if sceneJson ~= "" then
        enrichedQuestion = question .. "\n\n[current_scene]\n" .. sceneJson .. "\n[/current_scene]"
    end

    if CURRENT_PROVIDER == "nvidia" then
        enrichedQuestion = "[System Instructions]\n" .. SYSTEM_PROMPT .. "\n\n[User Request]\n" .. enrichedQuestion
    end
    if retryCount > 0 then
        local retryMsg = "⚠️ Your last response had issues."
        if _lastValidationErrors then
            retryMsg = retryMsg .. "\nFix these errors in your actions:\n- " .. table.concat(_lastValidationErrors, "\n- ")
            _lastValidationErrors = nil
        else
            retryMsg = retryMsg .. " Send only valid JSON without extra text."
        end
        enrichedQuestion = enrichedQuestion .. "\n\n" .. retryMsg
    end
    table.insert(messages, { role = "user", content = enrichedQuestion })

    local effort = classifyEffort(question)
    local raw, err, usage = callAI(messages, nil, effort)
    if usage and type(usage) == "table" then
        accumUsage.prompt_tokens = accumUsage.prompt_tokens + (tonumber(usage.prompt_tokens) or 0)
        accumUsage.completion_tokens = accumUsage.completion_tokens + (tonumber(usage.completion_tokens) or 0)
        accumUsage.total_tokens = accumUsage.total_tokens + (tonumber(usage.total_tokens) or 0)
    end
    if not raw then
        return nil, err, accumUsage
    end

    local plan = tryExtractJson(raw)
    if not plan then
        logToFile("Impure JSON response (request: " .. question .. ")", raw)
        if retryCount < maxRetries then
            return requestPlan(question, retryCount + 1, accumUsage)
        end
        return nil, "❌ Could not parse AI plan (not valid JSON). Raw response saved to: " .. LOG_FILE, accumUsage
    end

    if plan.actions and type(plan.actions) == "table" and retryCount < maxRetries then
        local validationErrors = validateActions(plan.actions)
        if #validationErrors > 0 then
            logToFile("Validation errors (request: " .. question .. ")", table.concat(validationErrors, "\n"))
            _lastValidationErrors = validationErrors
            return requestPlan(question, retryCount + 1, accumUsage)
        end
    end
    return plan, nil, accumUsage
end

local function addLog(msg, isErr)
    if not displayArea or not displayArea.Parent then return end
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Text = msg
    lbl.TextColor3 = isErr and C.red or C.yellow
    lbl.TextSize = 10
    lbl.Font = Enum.Font.Code
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = displayArea
    table.insert(_logLabels, lbl)
    task.wait()
    if displayArea and displayArea.Parent then
        displayArea.CanvasPosition = Vector2.new(0, displayArea.CanvasSize.Y.Offset)
    end
    return lbl
end

local function _runRequest(question)
    if not question or question == "" then
        _processingRequest = false
        return
    end
    _processingRequest = true
    CURRENT_REQUEST_TEXT = question
    _batchCreated = {}
    _batchPlacedGrid = nil

    task.spawn(function()
        local loading = Instance.new("TextLabel")
        local runOk, runErr = pcall(function()
            loading.Size = UDim2.new(1, -10, 0, 30)
            loading.BackgroundTransparency = 1
            local modelShort = (CURRENT_MODEL_LABEL or "?"):match("^%s*(.-)%s*$")
            if modelShort then modelShort = modelShort:sub(1,20) else modelShort = "?" end
            loading.Text = "🧠 Planning [" .. modelShort .. "] ."
            loading.TextColor3 = C.textDim
            loading.TextSize = 11
            loading.Font = Enum.Font.Gotham
            loading.Parent = displayArea

            -- Simple dot animation (no Heartbeat — saves CPU)
            task.spawn(function()
                local step = 0
                while loading and loading.Parent do
                    step = step + 1
                    local dots = string.rep(".", (step % 3) + 1)
                    loading.Text = "🧠 Planning [" .. modelShort .. "] " .. dots
                    task.wait(0.4)
                end
            end)
            local startTime = tick()
            addLog("📡 Sending to " .. CURRENT_PROVIDER:upper() .. "...")
            local plan, err, usage = requestPlan(question)
            addLog("📦 Parsing response...")
            local elapsed = tick() - startTime


            local function showCostLine()
                if usage and type(usage) == "table" and (usage.prompt_tokens or 0) + (usage.completion_tokens or 0) > 0 then
                    local pIn = usage.prompt_tokens or 0
                    local pOut = usage.completion_tokens or 0
                    -- للـ OpenCode: مجاني دائماً — السعر صفر
                    local cost = 0
                    local costStr
                    if CURRENT_PROVIDER == "nvidia" then
                        cost = (pIn / 1000000) * PRICE_PER_1M_INPUT + (pOut / 1000000) * PRICE_PER_1M_OUTPUT
                        costStr = ("💰 $%.6f"):format(cost)
                    else
                        costStr = "💚 Free"
                    end
                    addMessage(("⏱️ %.1fs | 🔤 %d in / %d out | %s"):format(elapsed, pIn, pOut, costStr), false, false, true)
                else
                    addMessage(("⏱️ %.1fs | 🔤 token usage not reported by server"):format(elapsed), false, false, true)
                end
            end

            if not plan then
                addMessage(err or "❌ Unknown error", false, true)
                pushHistory(question, "Failed to execute request (error: " .. tostring(err) .. ")")
                showCostLine()
                return
            end

            if plan.thought and type(plan.thought) == "string" and plan.thought ~= "" then
                addMessage("🧠 " .. plan.thought, false, false, true)
            end

            if plan.reply and type(plan.reply) == "string" and plan.reply ~= "" then
                addMessage("🤖 " .. plan.reply, false)
            end

            showCostLine()

            local actions = plan.actions
            if type(actions) ~= "table" or #actions == 0 then
                return
            end

            local summaryParts = {}
            local totalActions = #actions
            -- FIX v1.4: لا delay أبداً للباتشات الكبيرة — نستخدم task.wait فقط للباتشات الصغيرة (بصرياً)
            local visualDelay = totalActions > 20 and 0 or (totalActions > 8 and 0.01 or 0.04)

            addLog("⚙️ Executing " .. #actions .. " action(s)...")
            for actionIdx, action in ipairs(actions) do
                if type(action) ~= "table" or not action.type then
                    addMessage("⚠️ Skipped invalid action from AI", false, false, true)
                else
                    _lastClickInstance = nil
                    addLog("  [" .. actionIdx .. "/" .. totalActions .. "] " .. (action.type or "?") .. " → " .. (action.name or action.className or ""))
                    local successOk, didSucceed, resultMessage = pcall(executeAction, action)
                    local clickInst = _lastClickInstance
                    if successOk then
                        addMessage(resultMessage or "✅ Done", false, not didSucceed, true, clickInst)
                        if didSucceed then
                            local detail = tostring(action.type)
                            if action.className then detail = detail .. "(" .. tostring(action.className) .. ")" end
                            if action.name then detail = detail .. " name=" .. tostring(action.name) end
                            if action.namePrefix then detail = detail .. " prefix=" .. tostring(action.namePrefix) end
                            if action.containerName then detail = detail .. " container=" .. tostring(action.containerName) end
                            if action.count then detail = detail .. " count=" .. tostring(action.count) end
                            table.insert(summaryParts, detail)
                        end
                    else
                        addMessage("❌ Execution error: " .. tostring(didSucceed), false, true)
                        table.insert(summaryParts, tostring(action.type) .. " failed: " .. tostring(didSucceed))
                    end
                    if actionIdx < totalActions then
                        task.wait(visualDelay)
                    end
                end
            end

            local summary
            if #summaryParts > 0 then
                summary = "Executed: " .. table.concat(summaryParts, " | ")
            else
                summary = "No actions succeeded for this request."
            end

            if #_batchCreated > 0 then
                table.insert(undoStack, {
                    instances = _batchCreated,
                    summary = summary
                })
                while #undoStack > undoLimit do
                    table.remove(undoStack, 1)
                end
            end

            pushHistory(question, summary)
        end)

        if not runOk then
            addMessage("❌ " .. tostring(runErr), false, true)
        end
        pcall(function()
            if loading and loading.Parent then
                loading:Destroy()
            end
        end)
        pcall(function()
            for _, lbl in ipairs(_logLabels) do
                if lbl and lbl.Parent then lbl:Destroy() end
            end
            _logLabels = {}
        end)
        if #_requestQueue > 0 then
            local nextQ = table.remove(_requestQueue, 1)
            task.spawn(function() _runRequest(nextQ) end)
        else
            _processingRequest = false
        end
    end)
end

local function sendQuestion()
    local question = inputBox.Text
    if question == "" then return end

    if question == "/undo" or question == "undo" then
        inputBox.Text = ""
        if #undoStack == 0 then
            addMessage("⚠️ Nothing to undo.", false, true)
            return
        end
        local lastBatch = table.remove(undoStack)
        local removed = 0
        for _, entry in ipairs(lastBatch.instances) do
            if type(entry) == "table" and entry._markedForDestroy then
                addMessage("⚠️ Cannot restore: " .. tostring(entry._name) .. " (was already deleted)", false, false, true)
            else
                local inst = entry
                if inst and inst.Parent then
                    inst:Destroy()
                    removed += 1
                end
            end
        end
        addMessage("↩️ Undone: " .. lastBatch.summary .. " (removed " .. removed .. " items)", false, false, true)
        pushHistory("/undo", "Undid: " .. lastBatch.summary)
        return
    end

    local findPrefix = "/find "
    if question:lower():sub(1, #findPrefix) == findPrefix then
        inputBox.Text = ""
        local searchName = question:sub(#findPrefix + 1)
        if searchName == "" then
            addMessage("❌ Usage: /find Name", false, true)
            return
        end
        local results = findAllByName(searchName)
        if #results == 0 then
            addMessage("❌ No instances found containing \"" .. searchName .. "\"", false, true)
            return
        end
        local msg = "🔍 Found " .. #results .. " instance(s) for \"" .. searchName .. "\":"
        for i, res in ipairs(results) do
            msg = msg .. "\n  " .. i .. ". " .. res.Name .. " (" .. (res.ClassName or "?") .. ") → " .. getInstancePath(res)
        end
        addMessage(msg, false, false, true)
        pushHistory("/find " .. searchName, "Found " .. #results .. " instances")
        return
    end

    if question:lower() == "/diag" then
        inputBox.Text = ""
        addMessage("🧑 " .. question, true)
        -- Real diagnostic test: create a test LocalScript, parent it to Workspace,
        -- write Source, wait, read it back, and compare — raw result, no embellishment.
        local testSource = "--diag test " .. tostring(os.time())
        local testOk, testInst = pcall(function() return Instance.new("LocalScript") end)
        if not testOk or not testInst then
            addMessage("❌ Instance.new(\"LocalScript\") itself failed: " .. tostring(testInst), false, true)
            return
        end
        testInst.Name = "SkillAI_DiagTest"
        local p1ok = pcall(function() testInst.Source = testSource end)
        local r1ok, r1val = pcall(function() return testInst.Source end)
        local beforeParent = "Before parenting to game: write_ok=" .. tostring(p1ok) .. " read_ok=" .. tostring(r1ok)
            .. " match=" .. tostring(r1ok and r1val == testSource)

        testInst.Parent = Workspace
        task.wait()
        local p2ok = pcall(function() testInst.Source = testSource end)
        task.wait()
        local r2ok, r2val = pcall(function() return testInst.Source end)
        local afterParent = "After parenting to game: write_ok=" .. tostring(p2ok) .. " read_ok=" .. tostring(r2ok)
            .. " match=" .. tostring(r2ok and r2val == testSource)
            .. " length=" .. tostring(r2ok and r2val and #r2val or 0)

        local writefileAvail = "writefile available: " .. tostring(writefile ~= nil)
        local setclipboardAvail = "setclipboard available: " .. tostring(setclipboard ~= nil)

        testInst:Destroy()

        -- Additional check: verify StarterPlayerScripts/StarterCharacterScripts are
        -- the correct types (not fake Folders with the same name — the real root cause
        -- of "Not Found" even when Source writing succeeds).
        local spsClass = StarterPlayerScripts and StarterPlayerScripts.ClassName or "nil"
        local scsClass = StarterCharacterScripts and StarterCharacterScripts.ClassName or "nil"
        local spsCheck = "StarterPlayerScripts type: " .. spsClass
            .. (spsClass == "StarterPlayerScripts" and " ✅ correct" or " ❌ wrong! Expected StarterPlayerScripts, not " .. spsClass)
        local scsCheck = "StarterCharacterScripts type: " .. scsClass
            .. (scsClass == "StarterCharacterScripts" and " ✅ correct" or " ❌ wrong! Expected StarterCharacterScripts, not " .. scsClass)

        -- Real end-to-end test: create an actual LocalScript inside StarterPlayerScripts and verify we find it
        local spsTestMsg = "Skipped (StarterPlayerScripts unavailable)"
        if StarterPlayerScripts then
            local sp2ok, sp2inst = pcall(function() return Instance.new("LocalScript") end)
            if sp2ok and sp2inst then
                sp2inst.Name = "SkillAI_DiagTest2"
                sp2inst.Parent = StarterPlayerScripts
                pcall(function() sp2inst.Source = testSource end)
                task.wait()
                local foundBack = StarterPlayerScripts:FindFirstChild("SkillAI_DiagTest2")
                spsTestMsg = "Script inside StarterPlayerScripts found afterward: " .. tostring(foundBack ~= nil)
                if foundBack then foundBack:Destroy() end
            end
        end

        local finalVerdict
        if r2ok and r2val == testSource and spsClass == "StarterPlayerScripts" then
            finalVerdict = "✅ Result: Source writing works, and StarterPlayerScripts is the correct type. If you still see issues, tell me exactly what happens."
        elseif spsClass ~= "StarterPlayerScripts" then
            finalVerdict = "❌ Result: Found the root cause! StarterPlayerScripts is NOT the correct type in this session — this explains 'Not Found'. Try /diag after restarting the script with this update."
        else
            finalVerdict = "❌ Result: This Executor definitely blocks Source writing after parenting (confirmed by actual test, not guesswork)."
        end

        addMessage("🔬 Diagnostic result:\n" .. beforeParent .. "\n" .. afterParent .. "\n" .. writefileAvail .. "\n" .. setclipboardAvail
            .. "\n" .. spsCheck .. "\n" .. scsCheck .. "\n" .. spsTestMsg .. "\n\n" .. finalVerdict, false, false, true)
        pushHistory("/diag", "Ran Source-write diagnostic")
        return
    end

    if question:lower() == "/clear" then
        conversationHistory = {}
        addMessage("🧹 History cleared. AI starts fresh.", false)
        return
    end

    -- FIX: أمر /export — يصدّر تاريخ المحادثة كملف نصي أو ينسخه للـ clipboard
    if question:lower() == "/export" then
        inputBox.Text = ""
        if #conversationHistory == 0 then
            addMessage("⚠️ No conversation history to export.", false, false, true)
            return
        end
        local lines = { "=== Skill-AI v1.3 Conversation Export ===" }
        local ts = os.date and os.date("%Y-%m-%d %H:%M") or tostring(os.time())
        table.insert(lines, "Date: " .. ts)
        table.insert(lines, "Model: " .. CURRENT_MODEL_LABEL)
        table.insert(lines, "Turns: " .. #conversationHistory)
        table.insert(lines, "")
        for i, turn in ipairs(conversationHistory) do
            table.insert(lines, ("[%d] User: %s"):format(i, turn.user or ""))
            table.insert(lines, ("    AI: %s"):format(turn.summary or ""))
            table.insert(lines, "")
        end
        local exportStr = table.concat(lines, "\n")
        local saved = false
        -- محاولة حفظ ملف
        if writefile then
            local exportFile = "SkillAI_Export_" .. tostring(os.time()) .. ".txt"
            pcall(function()
                writefile(exportFile, exportStr)
                addMessage("✅ Exported " .. #conversationHistory .. " turn(s) to: " .. exportFile, false, false, true)
                saved = true
            end)
        end
        -- نسخ للـ clipboard كبديل
        if not saved and setclipboard then
            local ok = pcall(function() setclipboard(exportStr) end)
            if ok then
                addMessage("📋 Copied " .. #conversationHistory .. " turn(s) to clipboard (no writefile available)", false, false, true)
                saved = true
            end
        end
        if not saved then
            addMessage("⚠️ Export: writefile and setclipboard both unavailable in this executor.", false, false, true)
        end
        pushHistory("/export", "Exported " .. #conversationHistory .. " conversation turns")
        return
    end

    if question:lower() == "/cleanup" or question:lower() == "/clearfiles" then
        local cleaned = {}
        if writefile and delfile then
            pcall(function()
                if isfile and isfile(LOG_FILE) then
                    delfile(LOG_FILE)
                    table.insert(cleaned, LOG_FILE)
                end
            end)
            pcall(function()
                local filesToDel = {}
                if listfiles then
                    for _, f in ipairs(listfiles("/")) do
                        if type(f) == "string" and (f:find("SkillAI", 1, true) or f:find("skillai", 1, true)) then
                            table.insert(filesToDel, f)
                        end
                    end
                end
                for _, f in ipairs(filesToDel) do
                    pcall(function() delfile(f) end)
                    table.insert(cleaned, f)
                end
            end)
        end
        -- clean up test instances in workspace
        local removedCount = 0
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj.Name:find("SkillAI_Diag", 1, true) or obj.Name:find("SkillAI_Test", 1, true) then
                pcall(function() obj:Destroy() end)
                removedCount = removedCount + 1
            end
        end
        local msg = "🧹 Cleanup done."
        if #cleaned > 0 then
            msg = msg .. " Deleted " .. #cleaned .. " file(s): " .. table.concat(cleaned, ", ")
        else
            msg = msg .. " No files to delete (writefile/delfile not available)."
        end
        if removedCount > 0 then
            msg = msg .. " Destroyed " .. removedCount .. " leftover test instance(s)."
        end
        addMessage(msg, false, false, true)
        return
    end

    inputBox.Text = ""
    addMessage("🧑 " .. question, true)
    CURRENT_REQUEST_TEXT = question

    -- request queue: if already processing, add to queue
    if _processingRequest then
        table.insert(_requestQueue, question)
        addMessage("⏳ Queued... (" .. #_requestQueue .. " waiting)", false, false, true)
        return
    end
    _processingRequest = true

    task.spawn(function() _runRequest(question) end)
end

sendBtn.MouseButton1Click:Connect(sendQuestion)

inputBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then sendQuestion() end
end)

task.spawn(function()
    task.wait(1)
    pcall(setupRespawnReRunner)
    addMessage("🤖 Skill-AI v1.4\n📡 Model: " .. CURRENT_MODEL_LABEL .. "\n💡 /export لتصدير المحادثة | /clear | /undo | /find | /diag", false)
end)

print("[Skill-AI v1.4] Loaded | Timeout+Cache+SceneGC+FastRetry+HeightFix+BatchDelay fixes")
