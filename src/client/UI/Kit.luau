--[[
	UI Kit: tiny helpers for the chunky, cartoon, mobile-first style.

	Design rules:
	  * FredokaOne everywhere, thick dark outlines, rounded corners
	  * Minimum touch target 56px (scaled by UIScale for small phones)
	  * Rarity colours are the only saturated colours on cards
	  * No images or uploaded icons: emoji + shapes only
]]

local TweenService = game:GetService("TweenService")

local Kit = {}

Kit.Font = Enum.Font.FredokaOne
Kit.Colors = {
	Panel = Color3.fromRGB(34, 36, 52),
	PanelLight = Color3.fromRGB(52, 56, 78),
	Stroke = Color3.fromRGB(14, 14, 22),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(180, 186, 210),
	Green = Color3.fromRGB(76, 214, 96),
	Blue = Color3.fromRGB(70, 150, 255),
	Red = Color3.fromRGB(240, 70, 80),
	Gold = Color3.fromRGB(255, 196, 40),
	Purple = Color3.fromRGB(170, 90, 255),
	Pink = Color3.fromRGB(255, 90, 200),
	Coins = Color3.fromRGB(255, 208, 60),
	Mutagen = Color3.fromRGB(120, 255, 140),
	Gems = Color3.fromRGB(90, 220, 255),
}

-- Kit.new("Frame", { Size = ..., Parent = ... }, { children })
function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	local properties: { [string]: any } = props or {}
	for key, value in properties do
		if key == "Parent" then
			parent = value
		else
			(inst :: any)[key] = value
		end
	end
	local kids: { Instance } = children or {}
	for _, child in kids do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Kit.corner(radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 14) })
end

function Kit.stroke(thickness: number?, color: Color3?): UIStroke
	return Kit.new("UIStroke", {
		Thickness = thickness or 3,
		Color = color or Kit.Colors.Stroke,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Kit.textStroke(thickness: number?): UIStroke
	return Kit.new("UIStroke", { Thickness = thickness or 2, Color = Kit.Colors.Stroke })
end

function Kit.padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return Kit.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Kit.list(direction: Enum.FillDirection, padding: number, align: Enum.HorizontalAlignment?): UIListLayout
	return Kit.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
end

function Kit.label(text: string, size: number, color: Color3?, props: { [string]: any }?): TextLabel
	local p = {
		BackgroundTransparency = 1,
		Font = Kit.Font,
		Text = text,
		TextSize = size,
		TextColor3 = color or Kit.Colors.Text,
		Size = UDim2.new(1, 0, 0, size + 6),
		TextWrapped = true,
	}
	local extra: { [string]: any } = props or {}
	for k, v in extra do
		p[k] = v
	end
	return Kit.new("TextLabel", p, { Kit.textStroke(math.max(1.5, size / 14)) })
end

-- Chunky button with a darker "3D" bottom lip and a press bounce.
function Kit.button(text: string, color: Color3, props: { [string]: any }?, onClick: (() -> ())?): TextButton
	local p = {
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Font = Kit.Font,
		Text = text,
		TextSize = 20,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(140, 50),
	}
	local extra: { [string]: any } = props or {}
	for k, v in extra do
		p[k] = v
	end
	local btn = Kit.new("TextButton", p, {
		Kit.corner(12),
		Kit.stroke(3),
		Kit.textStroke(2),
		Kit.new("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
			Rotation = 90,
		}),
	})
	local scale = Kit.new("UIScale", { Parent = btn })
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	if onClick then
		btn.Activated:Connect(onClick)
	end
	return btn
end

function Kit.panel(props: { [string]: any }?): Frame
	local p = {
		BackgroundColor3 = Kit.Colors.Panel,
		BorderSizePixel = 0,
	}
	local extra: { [string]: any } = props or {}
	for k, v in extra do
		p[k] = v
	end
	return Kit.new("Frame", p, { Kit.corner(18), Kit.stroke(4) })
end

function Kit.pop(inst: GuiObject)
	local scale = inst:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = inst })
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function Kit.clear(container: Instance, keepClass: { string }?)
	for _, child in container:GetChildren() do
		if not (keepClass and table.find(keepClass, child.ClassName)) then
			child:Destroy()
		end
	end
end

return Kit
