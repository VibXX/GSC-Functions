-- Plays animations by asset id on a character's Animator, caching tracks.
-- Empty ids are ignored, so missing animations never break gameplay.

local Anim = {}

local cache = setmetatable({}, { __mode = "k" }) -- [Animator] = { [id] = AnimationTrack }

local function animatorOf(character: Model?): Animator?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator")
end

function Anim.Load(character: Model?, id: string?): AnimationTrack?
	if not id or id == "" then
		return nil
	end
	local animator = animatorOf(character)
	if not animator then
		return nil
	end
	cache[animator] = cache[animator] or {}
	local track = cache[animator][id]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok then
			return nil
		end
		track = loaded
		cache[animator][id] = track
	end
	return track
end

function Anim.Play(character: Model?, id: string?, fade: number?, weight: number?, speed: number?): AnimationTrack?
	local track = Anim.Load(character, id)
	if track then
		track:Play(fade or 0.08, weight or 1, speed or 1)
	end
	return track
end

function Anim.Stop(character: Model?, id: string?, fade: number?)
	local track = Anim.Load(character, id)
	if track and track.IsPlaying then
		track:Stop(fade or 0.15)
	end
end

return Anim
