--[[
	Grow Your Pets: Animal Farm — client bootstrap. Order matters: state first, then the
	renderer (so entity spawns queue into it), then UI and input.
]]

local Client = script.Parent
local Controllers = Client.Controllers
local UI = Client.UI

local ClientState = require(Client.ClientState)
local FX = require(Controllers.FX)
local EntityRenderer = require(Controllers.EntityRenderer)
local Cinematics = require(Controllers.Cinematics)
local HUD = require(UI.HUD)
local MountController = require(Controllers.MountController)
local WorldClient = require(Controllers.WorldClient)

ClientState.Start()
FX.Start()
EntityRenderer.Start()
Cinematics.Start()
HUD.Start()
MountController.Start()
WorldClient.Start()
