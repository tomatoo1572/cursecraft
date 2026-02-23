class_name VoxelPalette
extends RefCounted

static func color_for_block_id(block_id: String) -> Color:
	match block_id:
		"core:grass":
			return Color(0.25, 0.75, 0.25)
		"core:dirt":
			return Color(0.45, 0.30, 0.18)
		"core:stone":
			return Color(0.55, 0.55, 0.55)
		"core:cobblestone":
			return Color(0.45, 0.45, 0.45)
		"core:sand":
			return Color(0.85, 0.80, 0.55)
		_:
			return Color(0.9, 0.1, 0.9) # magenta = missing/unknown
