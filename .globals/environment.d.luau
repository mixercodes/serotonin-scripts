-- Serotonin API type definitions for luau-lsp autocomplete.
-- This file is NOT executed at runtime.
-- Verified against build version-2e6461290a3541f5 via deftsolutions community docs.
-- Where these stubs and runtime behavior disagree, runtime takes precedence.

-- ================================================================
-- Roblox type stubs (Serotonin wraps Roblox objects)
-- ================================================================

type Attribute = {
	Name: string,
	TypeName: string,
	Value: any,
}

export type Instance = {
	-- Core
	Parent: Instance?,
	Name: string,
	ClassName: string,
	Address: string?,
	[any]: any,

	-- Hierarchy
	GetChildren: (self: Instance) -> { Instance },
	GetDescendants: (self: Instance) -> { Instance },
	FindFirstChild: (self: Instance, name: string) -> Instance?,
	FindFirstChildOfClass: (self: Instance, className: string) -> Instance?,
	FindFirstAncestor: (self: Instance, name: string) -> Instance?,
	FindFirstAncestorOfClass: (self: Instance, className: string) -> Instance?,
	FindFirstDescendant: (self: Instance, name: string) -> Instance?,
	FindFirstDescendantOfClass: (self: Instance, className: string) -> Instance?,

	-- Type checks
	IsA: (self: Instance, className: string) -> boolean,
	IsDescendantOf: (self: Instance, ancestor: Instance) -> boolean,
	IsAncestorOf: (self: Instance, descendant: Instance) -> boolean,

	-- Highlight
	SetHighlightOnTop: (self: Instance) -> (),
	SetHighlightTransparency: (self: Instance, transparency: number) -> (),

	-- Attributes
	GetAttributes: (self: Instance) -> { Attribute },
	GetAttribute: (self: Instance, name: string) -> Attribute?,
	GetFirstAttributeOfType: (self: Instance, typeName: string) -> Attribute?,
}

-- ================================================================
-- Vector3
-- ================================================================

export type Vector3 = {
	X: number,
	Y: number,
	Z: number,
	Magnitude: number,
	Unit: Vector3,

	Dot: (self: Vector3, other: Vector3) -> number,
	dot: (self: Vector3, other: Vector3) -> number,

	Cross: (self: Vector3, other: Vector3) -> Vector3,
	cross: (self: Vector3, other: Vector3) -> Vector3,

	Lerp: (self: Vector3, goal: Vector3, t: number) -> Vector3,
	lerp: (self: Vector3, goal: Vector3, t: number) -> Vector3,

	Floor: (self: Vector3) -> Vector3,
	floor: (self: Vector3) -> Vector3,

	Ceil: (self: Vector3) -> Vector3,
	ceil: (self: Vector3) -> Vector3,

	Abs: (self: Vector3) -> Vector3,
	abs: (self: Vector3) -> Vector3,

	Sign: (self: Vector3) -> Vector3,
	sign: (self: Vector3) -> Vector3,

	Min: (self: Vector3, other: Vector3) -> Vector3,
	min: (self: Vector3, other: Vector3) -> Vector3,

	Max: (self: Vector3, other: Vector3) -> Vector3,
	max: (self: Vector3, other: Vector3) -> Vector3,

	Angle: (self: Vector3, other: Vector3) -> number,
	angle: (self: Vector3, other: Vector3) -> number,

	-- Note: == is identity-only, not value equality. Use FuzzyEq for value comparison.
	FuzzyEq: (self: Vector3, other: Vector3, epsilon: number?) -> boolean,
	fuzzyeq: (self: Vector3, other: Vector3, epsilon: number?) -> boolean,
}

declare Vector3: {
	new: (x: number?, y: number?, z: number?) -> Vector3,

	-- Static constants (pre-allocated, use these on hot paths)
	zero:  Vector3,
	one:   Vector3,
	xAxis: Vector3,
	yAxis: Vector3,
	zAxis: Vector3,

	-- Static call forms
	Dot:     (a: Vector3, b: Vector3) -> number,
	Cross:   (a: Vector3, b: Vector3) -> Vector3,
	Lerp:    (a: Vector3, b: Vector3, t: number) -> Vector3,
	Floor:   (v: Vector3) -> Vector3,
	Ceil:    (v: Vector3) -> Vector3,
	Abs:     (v: Vector3) -> Vector3,
	Sign:    (v: Vector3) -> Vector3,
	Min:     (a: Vector3, b: Vector3) -> Vector3,
	Max:     (a: Vector3, b: Vector3) -> Vector3,
	Angle:   (a: Vector3, b: Vector3) -> number,
	FuzzyEq: (a: Vector3, b: Vector3, epsilon: number?) -> boolean,
}

-- ================================================================
-- Color3
-- ================================================================

export type Color3 = {
	-- Channels are 0..1 floats internally. tostring() prints 0..255 bytes.
	R: number,
	G: number,
	B: number,

	ToHex: (self: Color3) -> string,
	toHex: (self: Color3) -> string,
	to_hex: (self: Color3) -> string,

	-- Returns 3 values: h, s, v each in 0..1
	ToHSV: (self: Color3) -> (number, number, number),
	toHSV: (self: Color3) -> (number, number, number),
	to_h_s_v: (self: Color3) -> (number, number, number),

	Lerp: (self: Color3, other: Color3, t: number) -> Color3,
	lerp: (self: Color3, other: Color3, t: number) -> Color3,
}

declare Color3: {
	new:     (r: number, g: number, b: number) -> Color3,
	fromRGB: (r: number, g: number, b: number) -> Color3,
	FromRGB: (r: number, g: number, b: number) -> Color3,
	from_r_g_b: (r: number, g: number, b: number) -> Color3,
	fromHex: (hex: string) -> Color3,
	FromHex: (hex: string) -> Color3,
	from_hex: (hex: string) -> Color3,
	fromHSV: (h: number, s: number, v: number) -> Color3,
	FromHSV: (h: number, s: number, v: number) -> Color3,
	from_h_s_v: (h: number, s: number, v: number) -> Color3,
}

-- ================================================================
-- draw
-- ================================================================

-- 2D point for Polyline / ConvexPolyFilled: { x, y }
export type DrawPoint = { number }

export type Draw = {
	Line: (x1: number, y1: number, x2: number, y2: number, color: Color3, thickness: number?, alpha: number?) -> (),
	line: (x1: number, y1: number, x2: number, y2: number, color: Color3, thickness: number?, alpha: number?) -> (),

	Rect: (x: number, y: number, w: number, h: number, color: Color3, thickness: number?, rounding: number?, alpha: number?) -> (),
	rect: (x: number, y: number, w: number, h: number, color: Color3, thickness: number?, rounding: number?, alpha: number?) -> (),

	RectFilled: (x: number, y: number, w: number, h: number, color: Color3, rounding: number?, alpha: number?) -> (),
	rectFilled: (x: number, y: number, w: number, h: number, color: Color3, rounding: number?, alpha: number?) -> (),
	rect_filled: (x: number, y: number, w: number, h: number, color: Color3, rounding: number?, alpha: number?) -> (),

	Circle: (x: number, y: number, radius: number, color: Color3, thickness: number?, segments: number?, alpha: number?) -> (),
	circle: (x: number, y: number, radius: number, color: Color3, thickness: number?, segments: number?, alpha: number?) -> (),

	CircleFilled: (x: number, y: number, radius: number, color: Color3, segments: number?, alpha: number?) -> (),
	circleFilled: (x: number, y: number, radius: number, color: Color3, segments: number?, alpha: number?) -> (),
	circle_filled: (x: number, y: number, radius: number, color: Color3, segments: number?, alpha: number?) -> (),

	Triangle: (x1: number, y1: number, x2: number, y2: number, x3: number, y3: number, color: Color3, thickness: number?, alpha: number?) -> (),
	triangle: (x1: number, y1: number, x2: number, y2: number, x3: number, y3: number, color: Color3, thickness: number?, alpha: number?) -> (),

	TriangleFilled: (x1: number, y1: number, x2: number, y2: number, x3: number, y3: number, color: Color3, alpha: number?) -> (),
	triangleFilled: (x1: number, y1: number, x2: number, y2: number, x3: number, y3: number, color: Color3, alpha: number?) -> (),
	triangle_filled: (x1: number, y1: number, x2: number, y2: number, x3: number, y3: number, color: Color3, alpha: number?) -> (),

	Gradient: (x: number, y: number, w: number, h: number, startColor: Color3, endColor: Color3, isHorizontal: boolean, startAlpha: number?, endAlpha: number?) -> (),
	gradient: (x: number, y: number, w: number, h: number, startColor: Color3, endColor: Color3, isHorizontal: boolean, startAlpha: number?, endAlpha: number?) -> (),

	-- arg#6 is Color3 tint (NOT raw r,g,b,a bytes — that signature was wrong and crashes)
	Image: (textureId: number, x: number, y: number, w: number, h: number, color: Color3?, alpha: number?) -> (),
	image: (textureId: number, x: number, y: number, w: number, h: number, color: Color3?, alpha: number?) -> (),

	Text: (text: string, x: number, y: number, color: Color3, font: string?, alpha: number?) -> (),
	text: (text: string, x: number, y: number, color: Color3, font: string?, alpha: number?) -> (),

	TextOutlined: (text: string, x: number, y: number, color: Color3, font: string?, alpha: number?) -> (),
	textOutlined: (text: string, x: number, y: number, color: Color3, font: string?, alpha: number?) -> (),
	text_outlined: (text: string, x: number, y: number, color: Color3, font: string?, alpha: number?) -> (),

	GetTextSize: (text: string, font: string?) -> (number, number),
	getTextSize: (text: string, font: string?) -> (number, number),
	get_text_size: (text: string, font: string?) -> (number, number),

	-- Returns w, h as two values (multi-return), same as cheat.GetWindowSize()
	GetScreenSize: () -> (number, number),
	getScreenSize: () -> (number, number),
	get_screen_size: () -> (number, number),

	ComputeConvexHull: (points: { DrawPoint }) -> { DrawPoint }?,
	computeConvexHull: (points: { DrawPoint }) -> { DrawPoint }?,
	compute_convex_hull: (points: { DrawPoint }) -> { DrawPoint }?,

	Polyline: (points: { DrawPoint }, color: Color3, closed: boolean, thickness: number, alpha: number?) -> (),
	polyline: (points: { DrawPoint }, color: Color3, closed: boolean, thickness: number, alpha: number?) -> (),

	ConvexPolyFilled: (points: { DrawPoint }, color: Color3, alpha: number?) -> (),
	convexPolyFilled: (points: { DrawPoint }, color: Color3, alpha: number?) -> (),
	convex_poly_filled: (points: { DrawPoint }, color: Color3, alpha: number?) -> (),

	GetPartCorners: (part: Instance) -> { Vector3 }?,
	getPartCorners: (part: Instance) -> { Vector3 }?,
	get_part_corners: (part: Instance) -> { Vector3 }?,

	-- Returns nil when mesh is not loaded or part has no mesh asset
	GetMesh: (part: Instance) -> any?,
	getMesh: (part: Instance) -> any?,
	get_mesh: (part: Instance) -> any?,
}

declare draw: Draw

-- ================================================================
-- audio
-- ================================================================

type Audio = {
	-- Blocking — do not call from onPaint with long durations
	Beep: (frequency: number, duration: number) -> (),
	beep: (frequency: number, duration: number) -> (),

	-- wavData must be valid WAV bytes — non-WAV input crashes the cheat (pcall cannot catch)
	PlaySound: (wavData: string, loop: boolean?, volume: number?, pitch: number?) -> (),
	playSound: (wavData: string, loop: boolean?, volume: number?, pitch: number?) -> (),
	play_sound: (wavData: string, loop: boolean?, volume: number?, pitch: number?) -> (),

	StopAll: () -> (),
	stopAll: () -> (),
	stop_all: () -> (),
}

declare audio: Audio

-- ================================================================
-- entity
-- ================================================================

type BoundingBox2D = {
	x: number,
	y: number,
	w: number,
	h: number,
}

type EntityPlayer = {
	Name: string,
	DisplayName: string,
	UserId: number,
	Team: string,
	Weapon: string,
	-- Position is frequently stale (0,0,0) in FFA modes — use GetBonePosition instead
	Position: Vector3,
	-- Normalized walk direction (magnitude ~1), NOT raw physics velocity. (0,0,0) when idle.
	Velocity: Vector3,
	Health: number,
	MaxHealth: number,
	IsAlive: boolean,
	IsEnemy: boolean,
	IsVisible: boolean,
	IsWhitelisted: boolean,
	BoundingBox: BoundingBox2D,
	-- Custom userdata: .R/.G/.B return 0..255 bytes (NOT 0..1 floats like Color3)
	TeamColor: any,

	GetBonePosition: (self: EntityPlayer, boneName: string) -> Vector3?,
	getBonePosition: (self: EntityPlayer, boneName: string) -> Vector3?,
	get_bone_position: (self: EntityPlayer, boneName: string) -> Vector3?,

	GetBoneInstance: (self: EntityPlayer, boneName: string) -> Instance?,
	getBoneInstance: (self: EntityPlayer, boneName: string) -> Instance?,
	get_bone_instance: (self: EntityPlayer, boneName: string) -> Instance?,

	-- Returns cheat hitbox size (5,5,5), not physical part size
	GetBoneSize: (self: EntityPlayer, boneName: string) -> Vector3?,
	getBoneSize: (self: EntityPlayer, boneName: string) -> Vector3?,
	get_bone_size: (self: EntityPlayer, boneName: string) -> Vector3?,

	-- Returns flat 9-element table (3x3 rotation matrix)
	GetBoneRotation: (self: EntityPlayer, boneName: string) -> { number }?,
	getBoneRotation: (self: EntityPlayer, boneName: string) -> { number }?,
	get_bone_rotation: (self: EntityPlayer, boneName: string) -> { number }?,
}

type EntityModelData = {
	Character: Instance,
	PrimaryPart: Instance,
	Name: string,
	DisplayName: string?,
	Team: string?,
	Weapon: string?,
	Humanoid: Instance?,
	HealthInstance: Instance?,
	Health: number?,
	MaxHealth: number?,
}

type Entity = {
	GetPlayers: (onlyEnemies: boolean?) -> { EntityPlayer },
	getPlayers: (onlyEnemies: boolean?) -> { EntityPlayer },
	get_players: (onlyEnemies: boolean?) -> { EntityPlayer },

	GetLocalPlayer: () -> EntityPlayer?,
	getLocalPlayer: () -> EntityPlayer?,
	get_local_player: () -> EntityPlayer?,

	GetTarget: () -> EntityPlayer?,
	getTarget: () -> EntityPlayer?,
	get_target: () -> EntityPlayer?,

	-- Returns integer indices; per-part read functions do NOT exist in this build
	GetParts: () -> { number },
	getParts: () -> { number },
	get_parts: () -> { number },

	GetPartsCount: () -> number,
	getPartsCount: () -> number,
	get_parts_count: () -> number,

	AddModel: (key: string, data: EntityModelData) -> boolean,
	addModel: (key: string, data: EntityModelData) -> boolean,
	add_model: (key: string, data: EntityModelData) -> boolean,

	EditModel: (key: string, data: EntityModelData) -> boolean,
	editModel: (key: string, data: EntityModelData) -> boolean,
	edit_model: (key: string, data: EntityModelData) -> boolean,

	RemoveModel: (key: string) -> boolean,
	removeModel: (key: string) -> boolean,
	remove_model: (key: string) -> boolean,

	ClearModels: () -> boolean,
	clearModels: () -> boolean,
	clear_models: () -> boolean,
}

declare entity: Entity

-- ================================================================
-- utility
-- ================================================================

-- GetMousePos returns {[1]=x, [2]=y} — access as mpos[1], mpos[2], NOT .x/.y
type MousePos = { number }

type SystemTime = {
	year: number,
	month: number,
	day: number,
	hour: number,
	minute: number,
	second: number,
	-- 0=Sunday, 1=Monday, ..., 6=Saturday (C tm_wday convention)
	weekday: number,
}

type Utility = {
	RandomInt: (min: number, max: number) -> number,
	randomInt: (min: number, max: number) -> number,
	random_int: (min: number, max: number) -> number,

	RandomFloat: (min: number, max: number) -> number,
	randomFloat: (min: number, max: number) -> number,
	random_float: (min: number, max: number) -> number,

	-- Milliseconds since cheat startup (NOT system boot)
	GetTickCount: () -> number,
	getTickCount: () -> number,
	get_tick_count: () -> number,

	GetDeltaTime: () -> number,
	getDeltaTime: () -> number,
	get_delta_time: () -> number,

	GetTimestamp: () -> number,
	getTimestamp: () -> number,
	get_timestamp: () -> number,

	GetSystemTime: () -> SystemTime,
	getSystemTime: () -> SystemTime,
	get_system_time: () -> SystemTime,

	-- Returns empty string "" in build version-2e6461290a3541f5 — always check for ""
	GetFingerprint: () -> string,
	getFingerprint: () -> string,
	get_fingerprint: () -> string,

	SetClipboard: (content: string) -> (),
	setClipboard: (content: string) -> (),
	set_clipboard: (content: string) -> (),

	GetClipboard: () -> string,
	getClipboard: () -> string,
	get_clipboard: () -> string,

	-- Relative offset in OS pointer units (NOT raw pixels — pointer acceleration applies)
	MoveMouse: (dx: number, dy: number) -> (),
	moveMouse: (dx: number, dy: number) -> (),
	move_mouse: (dx: number, dy: number) -> (),

	GetMousePos: () -> MousePos,
	getMousePos: () -> MousePos,
	get_mouse_pos: () -> MousePos,

	GetMenuState: () -> boolean,
	getMenuState: () -> boolean,
	get_menu_state: () -> boolean,

	-- onScreen=true means projection is valid (not necessarily within screen bounds)
	WorldToScreen: (position: Vector3) -> (number, number, boolean),
	worldToScreen: (position: Vector3) -> (number, number, boolean),
	world_to_screen: (position: Vector3) -> (number, number, boolean),

	-- Each call allocates a new texture handle — load once at startup, reuse the id
	LoadImage: (image_data: string) -> number?,
	loadImage: (image_data: string) -> number?,
	load_image: (image_data: string) -> number?,

	-- Joins a Roblox server by Job ID. Invalid IDs may disconnect from current server.
	TeleportToPlace: (jobId: string) -> (),
	teleportToPlace: (jobId: string) -> (),
	teleport_to_place: (jobId: string) -> (),
}

declare utility: Utility

-- ================================================================
-- input
-- ================================================================

-- IsClicked accepts: "left", "right", "mouse4", "mouse5", 0, 1, 2
-- Click/Press/Release accept: 1 (LMB), 2 (RMB), 4 (MMB), 5 (X1), 6 (X2), "mouse4", "mouse5"
-- "left"/"right" strings are NOT valid for Click/Press/Release — use numeric VK codes instead
type Mouse = {
	Click: (button: number | string) -> (),
	click: (button: number | string) -> (),

	Press: (button: number | string) -> (),
	press: (button: number | string) -> (),

	Release: (button: number | string) -> (),
	release: (button: number | string) -> (),

	IsClicked: (button: string | number) -> boolean,
	isClicked: (button: string | number) -> boolean,
	is_clicked: (button: string | number) -> boolean,

	Scroll: (delta: number) -> (),
	scroll: (delta: number) -> (),
}

-- Accepted key names: single letters "A"-"Z", digits "1"-"9", "F1"-"F12",
-- "Space", "Enter", "Escape", "Shift", "Ctrl", "Alt", or Windows VK integers.
-- "Return", "Esc", "LeftShift", "LeftControl", "LeftAlt" are NOT valid — use the forms above.
type Keyboard = {
	Press: (key: string | number) -> (),
	press: (key: string | number) -> (),

	Release: (key: string | number) -> (),
	release: (key: string | number) -> (),

	Click: (key: string | number, delay: number?) -> (),
	click: (key: string | number, delay: number?) -> (),

	IsPressed: (key: string | number) -> boolean,
	isPressed: (key: string | number) -> boolean,
	is_pressed: (key: string | number) -> boolean,
}

declare mouse: Mouse
declare keyboard: Keyboard

-- ================================================================
-- cheat
-- ================================================================

type Cheat = {
	-- Event names are case-sensitive: "onUpdate", "onPaint", "onSlowUpdate", "shutdown", "newPlace"
	-- Invalid event names are silently accepted but never fire
	Register: (eventName: string, callback: () -> ()) -> (),
	register: (eventName: string, callback: () -> ()) -> (),

	GetWindowSize: () -> (number, number),
	getWindowSize: () -> (number, number),
	get_window_size: () -> (number, number),

	-- BROKEN in build version-2e6461290a3541f5 — raises "C++ exception" on every call.
	-- Use loadstring(code)() instead.
	-- Arg order: name first, then code (opposite of old docs).
	LoadString: (name: string, code: string) -> (),
	loadString: (name: string, code: string) -> (),
	load_string: (name: string, code: string) -> (),
}

declare cheat: Cheat

-- ================================================================
-- memory
-- ================================================================

type MemoryType =
	"float" | "double"
	| "int" | "uint"
	| "bool" | "byte"
	| "short" | "ushort"
	| "int64" | "uint64"
	| "pointer" | "ptr"
	| "string"
	| "vector2" | "vector3"
	| "color3"
	| "cframe"
	-- NOT valid: "int8", "int16", "int32", "qword" — these raise "Invalid memory type"

type Memory = {
	Read: (memType: MemoryType, address: number) -> any,
	read: (memType: MemoryType, address: number) -> any,

	-- Write is dangerous — wrong address/type can crash. Always gate with IsValid.
	Write: (memType: MemoryType, address: number, value: any) -> (),
	write: (memType: MemoryType, address: number, value: any) -> (),

	GetBase: () -> number,
	getBase: () -> number,
	get_base: () -> number,

	Rebase: (offset: number) -> number,
	rebase: (offset: number) -> number,

	IsValid: (address: number) -> boolean,
	isValid: (address: number) -> boolean,
	is_valid: (address: number) -> boolean,

	-- Single-arg: returns first matching address (number) or nil.
	-- Two-arg (pattern, module): returns table of all matching addresses in that module.
	-- "returnAll" and "limit" params do NOT exist in this build.
	Scan: (pattern: string, module: string?) -> any,
	scan: (pattern: string, module: string?) -> any,
}

declare memory: Memory

-- ================================================================
-- file
-- ================================================================

-- listdir entry — size is only present when isFile == true
type FileEntry = {
	name: string,
	isDirectory: boolean,
	isFile: boolean,
	size: number?,
}

-- file.write does NOT create parent directories — use mkdir first.
-- ".." in paths raises an error. Absolute paths bypass the sandbox.
type File = {
	read: (filename: string) -> string?,
	Read: (filename: string) -> string?,

	-- Overwrites. Returns false (silent) if parent dir is missing.
	write: (filename: string, content: string) -> boolean,
	Write: (filename: string, content: string) -> boolean,

	-- Creates file if missing (unlike write). Returns true on success.
	append: (filename: string, content: string) -> boolean,
	Append: (filename: string, content: string) -> boolean,

	-- Deletes file or empty directory. Returns false for missing or non-empty dir.
	delete: (path: string) -> boolean,
	Delete: (path: string) -> boolean,

	exists: (path: string) -> boolean,
	Exists: (path: string) -> boolean,

	isdir: (path: string) -> boolean,
	IsDir: (path: string) -> boolean,
	isDir: (path: string) -> boolean,

	-- Recursive and idempotent (returns true if already exists)
	mkdir: (path: string) -> boolean,
	Mkdir: (path: string) -> boolean,

	-- Returns array of FileEntry records, nil for missing/non-directory paths
	listdir: (path: string?) -> { FileEntry }?,
	ListDir: (path: string?) -> { FileEntry }?,
	listDir: (path: string?) -> { FileEntry }?,
}

declare file: File

-- ================================================================
-- http
-- ================================================================

type Http = {
	Get: (url: string, headers: { [string]: string }, callback: (response: string?) -> ()) -> (),
	get: (url: string, headers: { [string]: string }, callback: (response: string?) -> ()) -> (),

	Post: (url: string, headers: { [string]: string }, body: string, callback: (response: string?) -> ()) -> (),
	post: (url: string, headers: { [string]: string }, body: string, callback: (response: string?) -> ()) -> (),
}

declare http: Http

-- ================================================================
-- websocket
-- ================================================================

type WebSocketCallbacks = {
	onOpen: (() -> ())?,
	onMessage: ((message: string) -> ())?,
	onClose: ((code: number, reason: string) -> ())?,
	onError: ((errorMsg: string) -> ())?,
}

type WebSocket = {
	Connect: (url: string, callbacks: WebSocketCallbacks) -> number,
	connect: (url: string, callbacks: WebSocketCallbacks) -> number,

	Send: (socketId: number, data: string) -> boolean,
	send: (socketId: number, data: string) -> boolean,

	Close: (socketId: number, code: number?, reason: string?) -> (),
	close: (socketId: number, code: number?, reason: string?) -> (),
}

declare websocket: WebSocket

-- ================================================================
-- ui
-- ================================================================

-- Colorpicker value table — use this shape for GetValue/SetValue, NOT Color3
type UIColor = { r: number, g: number, b: number, a: number }

-- GetHotkey return table
type HotkeyInfo = {
	key: number,       -- Windows VK code, 0 if unbound
	key_name: string,  -- display name e.g. "F8", "Unbound"
	mode: number,      -- trigger mode (0 = on hold)
}

type UI = {
	-- Returns nil (not a reference id)
	NewTab: (tab_ref: string, display_name: string) -> (),
	newTab: (tab_ref: string, display_name: string) -> (),
	new_tab: (tab_ref: string, display_name: string) -> (),

	-- Returns nil. No options table — just 3 required string args.
	NewContainer: (tab_ref: string, container_ref: string, display_name: string) -> (),
	newContainer: (tab_ref: string, container_ref: string, display_name: string) -> (),
	new_container: (tab_ref: string, container_ref: string, display_name: string) -> (),

	-- GetValue -> bool
	NewCheckbox: (tab_ref: string, container_ref: string, name: string) -> number,
	newCheckbox: (tab_ref: string, container_ref: string, name: string) -> number,
	new_checkbox: (tab_ref: string, container_ref: string, name: string) -> number,

	-- GetValue -> nil (buttons have no stored value)
	NewButton: (tab_ref: string, container_ref: string, name: string, callback_function: () -> ()) -> number,
	newButton: (tab_ref: string, container_ref: string, name: string, callback_function: () -> ()) -> number,
	new_button: (tab_ref: string, container_ref: string, name: string, callback_function: () -> ()) -> number,

	-- GetValue -> number (integer). Default is min.
	NewSliderInt: (tab_ref: string, container_ref: string, name: string, min: number, max: number) -> number,
	newSliderInt: (tab_ref: string, container_ref: string, name: string, min: number, max: number) -> number,
	new_slider_int: (tab_ref: string, container_ref: string, name: string, min: number, max: number) -> number,

	-- GetValue -> number (float). Default is min.
	NewSliderFloat: (tab_ref: string, container_ref: string, name: string, min: number, max: number) -> number,
	newSliderFloat: (tab_ref: string, container_ref: string, name: string, min: number, max: number) -> number,
	new_slider_float: (tab_ref: string, container_ref: string, name: string, min: number, max: number) -> number,

	-- GetValue -> string
	NewInputText: (tab_ref: string, container_ref: string, name: string) -> number,
	newInputText: (tab_ref: string, container_ref: string, name: string) -> number,
	new_input_text: (tab_ref: string, container_ref: string, name: string) -> number,

	-- GetValue -> number (1-based index, 0 = no selection). SetValue takes 1-based index, NOT the string.
	NewDropdown: (tab_ref: string, container_ref: string, name: string, options_table: { string }) -> number,
	newDropdown: (tab_ref: string, container_ref: string, name: string, options_table: { string }) -> number,
	new_dropdown: (tab_ref: string, container_ref: string, name: string, options_table: { string }) -> number,

	-- GetValue -> number (same shape as Dropdown)
	NewListbox: (tab_ref: string, container_ref: string, name: string, options_table: { string }) -> number,
	newListbox: (tab_ref: string, container_ref: string, name: string, options_table: { string }) -> number,
	new_listbox: (tab_ref: string, container_ref: string, name: string, options_table: { string }) -> number,

	-- GetValue -> {[1]=bool, [2]=bool, ...} (one bool per option, 1-based)
	NewMultiselect: (tab_ref: string, container_ref: string, name: string, options_table: { string }) -> number,
	newMultiselect: (tab_ref: string, container_ref: string, name: string, options_table: { string }) -> number,
	new_multiselect: (tab_ref: string, container_ref: string, name: string, options_table: { string }) -> number,

	-- GetValue -> UIColor {r,g,b,a} 0..255. SetValue takes UIColor, NOT Color3.
	NewColorpicker: (tab_ref: string, container_ref: string, name: string) -> number,
	newColorpicker: (tab_ref: string, container_ref: string, name: string) -> number,
	new_colorpicker: (tab_ref: string, container_ref: string, name: string) -> number,

	-- GetValue -> bool (true while bound key is held). SetValue takes Windows VK code number.
	NewHotkey: (tab_ref: string, container_ref: string, name: string) -> number,
	newHotkey: (tab_ref: string, container_ref: string, name: string) -> number,
	new_hotkey: (tab_ref: string, container_ref: string, name: string) -> number,

	GetValue: (tab_ref: string, container_ref: string, name: string) -> any?,
	getValue: (tab_ref: string, container_ref: string, name: string) -> any?,
	get_value: (tab_ref: string, container_ref: string, name: string) -> any?,

	SetValue: (tab_ref: string, container_ref: string, name: string, new_value: any) -> (),
	setValue: (tab_ref: string, container_ref: string, name: string, new_value: any) -> (),
	set_value: (tab_ref: string, container_ref: string, name: string, new_value: any) -> (),

	SetVisibility: (tab_ref: string, container_ref: string, name: string, is_visible: boolean) -> (),
	setVisibility: (tab_ref: string, container_ref: string, name: string, is_visible: boolean) -> (),
	set_visibility: (tab_ref: string, container_ref: string, name: string, is_visible: boolean) -> (),

	-- Returns {key, key_name, mode}. Use GetValue for the bool held-state instead.
	GetHotkey: (tab_ref: string, container_ref: string, name: string) -> HotkeyInfo?,
	getHotkey: (tab_ref: string, container_ref: string, name: string) -> HotkeyInfo?,
	get_hotkey: (tab_ref: string, container_ref: string, name: string) -> HotkeyInfo?,
}

declare ui: UI

-- ================================================================
-- game
-- ================================================================

type FFlagType = "bool" | "int" | "float" | "double"

type GameEx = {
	Workspace: Instance,
	Players: Instance,
	-- game.Lighting is nil in this build — use game.GetService("Lighting") instead
	LocalPlayer: Instance?,
	CameraPosition: Vector3,
	-- Note: game.DataModel, game.PlaceID, game.PlaceId crash the bridge — avoid in eval calls

	GetService: (serviceName: string) -> Instance?,
	getService: (serviceName: string) -> Instance?,
	get_service: (serviceName: string) -> Instance?,

	SilentAim: (x: number, y: number) -> (),
	silentAim: (x: number, y: number) -> (),
	silent_aim: (x: number, y: number) -> (),

	PlayerWhitelist: (name: string) -> (),
	playerWhitelist: (name: string) -> (),
	player_whitelist: (name: string) -> (),

	-- Now uses safer reads/writes (fixed in latest build). Bridge eval still auto-blocks these.
	GetFFlag: (name: string, flagType: FFlagType) -> any?,
	getFFlag: (name: string, flagType: FFlagType) -> any?,
	get_fflag: (name: string, flagType: FFlagType) -> any?,

	SetFFlag: (name: string, value: any, flagType: FFlagType) -> boolean,
	setFFlag: (name: string, value: any, flagType: FFlagType) -> boolean,
	set_fflag: (name: string, value: any, flagType: FFlagType) -> boolean,
}

declare game: GameEx

-- ================================================================
-- raknet  (vestigial — non-functional in modern Roblox builds)
-- ================================================================
-- is_connected() always returns false. add_send_hook callbacks never fire.
-- Single snake_case form only — no PascalCase or camelCase aliases.

type RakNet = {
	is_connected: () -> boolean,
	add_send_hook: (callback: (...any) -> ()) -> (),
	remove_send_hook: (callback: (...any) -> ()) -> (),
}

declare raknet: RakNet

-- ================================================================
-- bit  (LuaJIT-style 32-bit bitwise operations)
-- ================================================================
-- All results are signed int32. Shift counts are masked to low 5 bits (n & 31).
-- tobit rounds to nearest (not truncates). tohex: negative width = uppercase.
-- Single lowercase form only — no aliases.

type Bit = {
	band:    (...number) -> number,
	bor:     (...number) -> number,
	bxor:    (...number) -> number,
	bnot:    (a: number) -> number,
	lshift:  (a: number, n: number) -> number,
	rshift:  (a: number, n: number) -> number,
	arshift: (a: number, n: number) -> number,
	rol:     (a: number, n: number) -> number,
	ror:     (a: number, n: number) -> number,
	bswap:   (a: number) -> number,
	tobit:   (a: number) -> number,
	-- n > 0: lowercase, n < 0: uppercase. Default width is 8.
	tohex:   (a: number, n: number?) -> string,
}

declare bit: Bit

-- ================================================================
-- buffer  (fixed-size binary byte array)
-- ================================================================
-- Little-endian. Any byte offset is valid (no alignment requirement).
-- Out-of-bounds raises "buffer read/write out of bounds" (not a crash).
-- Integer writers silently wrap on overflow (no error for out-of-range values).
-- tostring(buf) returns raw byte content as a Lua string.
-- Single lowercase form only — no aliases.

type Buffer = any  -- __buffer userdata

type BufferLib = {
	-- Allocates size zeroed bytes. size >= 0.
	create:   (size: number) -> Buffer,
	len:      (buf: Buffer) -> number,

	readu8:   (buf: Buffer, offset: number) -> number,
	readu16:  (buf: Buffer, offset: number) -> number,
	readu32:  (buf: Buffer, offset: number) -> number,
	readi8:   (buf: Buffer, offset: number) -> number,
	readi16:  (buf: Buffer, offset: number) -> number,
	readi32:  (buf: Buffer, offset: number) -> number,
	readf32:  (buf: Buffer, offset: number) -> number,
	readf64:  (buf: Buffer, offset: number) -> number,

	writeu8:  (buf: Buffer, offset: number, value: number) -> (),
	writeu16: (buf: Buffer, offset: number, value: number) -> (),
	writeu32: (buf: Buffer, offset: number, value: number) -> (),
	writei8:  (buf: Buffer, offset: number, value: number) -> (),
	writei16: (buf: Buffer, offset: number, value: number) -> (),
	writei32: (buf: Buffer, offset: number, value: number) -> (),
	writef32: (buf: Buffer, offset: number, value: number) -> (),
	writef64: (buf: Buffer, offset: number, value: number) -> (),
}

declare buffer: BufferLib
