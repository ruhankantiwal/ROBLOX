-- Minimal Roblox datatype shims for running pure game modules headless.
local V = {}
V.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X*t.X + t.Y*t.Y + t.Z*t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X*t.X + t.Y*t.Y + t.Z*t.Z); return Vector3.new(t.X/m, t.Y/m, t.Z/m) end
	return V[k]
end
Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
Vector3.zero = Vector3.new(0, 0, 0)
V.__add = function(a, b) return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
V.__sub = function(a, b) return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
V.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then return Vector3.new(b.X*a, b.Y*a, b.Z*a) end
	if type(b) == "number" then return Vector3.new(a.X*b, a.Y*b, a.Z*b) end
	return Vector3.new(a.X*b.X, a.Y*b.Y, a.Z*b.Z)
end
V.__div = function(a, b)
	if type(b) == "number" then return Vector3.new(a.X/b, a.Y/b, a.Z/b) end
	return Vector3.new(a.X/b.X, a.Y/b.Y, a.Z/b.Z)
end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V.__tostring = function(a) return string.format("(%.2f, %.2f, %.2f)", a.X, a.Y, a.Z) end
function V.Dot(a, b) return a.X*b.X + a.Y*b.Y + a.Z*b.Z end
function V.Cross(a, b) return Vector3.new(a.Y*b.Z - a.Z*b.Y, a.Z*b.X - a.X*b.Z, a.X*b.Y - a.Y*b.X) end
function V.Lerp(a, b, t) return a + (b - a) * t end

local C = {}
C.__index = function(t, k)
	if k == "Position" then return Vector3.new(t.x, t.y, t.z) end
	if k == "X" then return t.x end
	if k == "Y" then return t.y end
	if k == "Z" then return t.z end
	if k == "Rotation" then return CFrame.fromMatrix(0, 0, 0, t.m) end
	if k == "LookVector" then return Vector3.new(-t.m[3], -t.m[6], -t.m[9]) end
	return C[k]
end
CFrame = {}
-- m = row-major 3x3 {r00 r01 r02 r10 r11 r12 r20 r21 r22}
function CFrame.fromMatrix(x, y, z, m) return setmetatable({ x = x, y = y, z = z, m = m }, C) end
local I = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
function CFrame.new(x, y, z)
	if type(x) == "table" then return CFrame.fromMatrix(x.X, x.Y, x.Z, I) end
	return CFrame.fromMatrix(x or 0, y or 0, z or 0, I)
end
local function mm(a, b)
	local r = {}
	for i = 0, 2 do for j = 0, 2 do
		local s = 0
		for k = 0, 2 do s += a[i*3+k+1] * b[k*3+j+1] end
		r[i*3+j+1] = s
	end end
	return r
end
local function mv(m, v) return Vector3.new(m[1]*v.X+m[2]*v.Y+m[3]*v.Z, m[4]*v.X+m[5]*v.Y+m[6]*v.Z, m[7]*v.X+m[8]*v.Y+m[9]*v.Z) end
function CFrame.Angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local Rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return CFrame.fromMatrix(0, 0, 0, mm(mm(Rx, Ry), Rz))
end
function CFrame.lookAt(at, target)
	local look = (target - at).Unit
	local right = look:Cross(Vector3.new(0, 1, 0)).Unit
	local up = right:Cross(look)
	return CFrame.fromMatrix(at.X, at.Y, at.Z, { right.X, up.X, -look.X, right.Y, up.Y, -look.Y, right.Z, up.Z, -look.Z })
end
C.__mul = function(a, b)
	if getmetatable(b) == V then return mv(a.m, b) + a.Position end
	local p = mv(a.m, b.Position) + a.Position
	return CFrame.fromMatrix(p.X, p.Y, p.Z, mm(a.m, b.m))
end
C.__add = function(a, v) return CFrame.fromMatrix(a.x+v.X, a.y+v.Y, a.z+v.Z, a.m) end
function C.Inverse(a)
	local m = a.m
	local t = { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
	local p = -mv(t, a.Position)
	return CFrame.fromMatrix(p.X, p.Y, p.Z, t)
end
function C.PointToWorldSpace(a, v) return a * v end
function C.VectorToWorldSpace(a, v) return mv(a.m, v) end
function C.PointToObjectSpace(a, v) return a:Inverse() * v end

local Col = {}
Col.__index = Col
Color3 = {}
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Col) end
function Color3.fromRGB(r, g, b) return Color3.new(r/255, g/255, b/255) end
function Color3.fromHSV(h, s, v) return Color3.new(v, v, v) end
function Col.Lerp(a, b, t) return Color3.new(a.R+(b.R-a.R)*t, a.G+(b.G-a.G)*t, a.B+(b.B-a.B)*t) end

local function enumProxy(path)
	return setmetatable({}, { __index = function(_, k) return enumProxy(path .. "." .. k) end, __tostring = function() return path end })
end
Enum = enumProxy("Enum")

Random = {}
Random.__index = Random
function Random.new(seed)
	return setmetatable({ s = (seed or 1) % 2147483647 }, Random)
end
function Random:NextNumber(a, b)
	self.s = (self.s * 16807) % 2147483647
	local r = self.s / 2147483647
	if a then return a + (b - a) * r end
	return r
end
function Random:NextInteger(a, b) return math.floor(self:NextNumber(a, b + 1 - 1e-9)) end
