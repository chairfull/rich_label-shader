# Rich Label

GPU-animated rich text for Godot 4. A drop-in `Control` that lays text out once on the CPU and then animates **every glyph on the GPU** through a generated `canvas_item` shader — waves, shakes, rainbows, glows and typewriter reveals with zero per-frame GDScript.

![Effect showcase](doc/showcase.png)

## Features

- **19 built-in effects** — wave, bob, skew, shake, tumble, rise, scatter, pop, fade, blur, shred, rainbow, outline, glow, drop shadow, tint, plus bold / italic / size / color
- **Typewriter intros & outros** — per-character, per-word or per-line stagger, with automatic pauses on punctuation and newlines
- **Links** — `[=id]click me]` with hover / click / right-click signals and tooltips
- **Inline images & scenes** — `~icon_id w=64` embeds textures or live subscenes in the text flow
- **Live data** — `$score` and `{score * 2}` bind to a context node
- **Custom effects** — new tags are a single GDScript file with a vertex/fragment snippet; no engine changes
- **Fast by construction** — one batched mesh per font atlas, generated shaders cached and reused, per-glyph state packed into uniform arrays

![Typewriter reveals](doc/reveal.png)

## Install

1. Copy `addons/rich_label` into your project's `addons/` folder (`addons/editor_helpers` goes with it).
2. **Project → Project Settings → Plugins**: enable **Rich Label**.
3. Add a **RichLabel** node from the Create Node dialog (it's registered as a custom type), or `RichLabel.new()` in code.

Requires Godot 4.x (developed against 4.8).

## Quick start

```gdscript
var label := RichLabel.new()
label.text = "[wave amp=4][24]Hello, [rainbow]world]!]"
add_child(label)
label.play_intro()   # typewriter reveal, per-character by default
```

Spans open with `[name ...]` and close with `]` (not `[/name]`). Nest them freely:
```
[b]bold [i]bold-italic]] and [red]red[/red] is wrong — close with ]
[b]bold [i]bold-italic]] — like this
```

> Godot's `[/tag]` closers are *not* closers here — `[/wave]` parses as an (unknown) tag literally named `/wave`. Just use `]`.

Multiple directives in one header are separated by `;`:

```
[wave amp=6; red]big wavy red text]
```

## Markup reference

| Syntax | Meaning |
|---|---|
| `[wave]text]` | Effect span (see tag table). Closes with `]`, nests freely |
| `[b]`, `[i]` | Faux bold / faux italic (font variations, no bold font file needed) |
| `[u]` | Underline (shader-rendered bar, follows effects) |
| `[s]`, `[strike]` | Strikethrough (shader-rendered bar, follows effects) |
| `[24]`, `[1.5]` | Absolute font size / relative scale |
| `[red]`, `[#ff8800]` | Named or hex color (any `Color.from_string` value) |
| `[tint color=#4fc3ff]` | Replace fill color for the span |
| `[left]` `[center]` `[right]` `[fill]` | Line alignment for the span |
| `[=some_id]text]` | Clickable link; `some_id` arrives on the link signals |
| `=bold=`, `_italic_` | Markdown-style inline bold / italic |
| `$score`, `$player.health` | Value from the label's `context` node |
| `{score * 2}` | GDScript expression evaluated against `context` |
| `~icon_id` | Inline image from the images dir |
| `~icon_id w=64 h=32` | …with size attrs (`width`/`w`, `height`/`h`) |
| `~icon_id fit=line valign=center` | `fit`: `line` (default) `none` `contain` `cover`; `valign`: `baseline` `top` `center` `bottom` |
| `~scene_id` | Inline live scene from the scenes dir |
| `\[`, `\]`, `\~`, `\$`, `\{`, `\\` | Escaped literals |

Unclosed spans are tolerated: a recognized tag left open at end-of-text stays applied to the end; an *unrecognized* `[...]` degrades to literal text.

## Tag reference

All tags accept `key=value` kwargs and/or positional args. Combine freely — `[wave][rainbow][glow]everything]]`.

Every motion tag also honors the global `strength=` and `speed=` multipliers (`[wave strength=2 speed=0.5]`), which scale that tag's intensity/frequency; a tag-specific param (`amp=`, `freq=`) always wins over the global alias for its own channel.

| Tag | Params | What it does |
|---|---|---|
| `wave` | `amplitude=4`, `frequency=1.5`, `phase_spread=0.4`, `axis=Vertical/Horizontal/Circular` | Rolling sine wave |
| `sin` | `amplitude=0.1`, `frequency=1.5`, `phase_spread=0.5` | Gentle vertical bob |
| `skew` | `amplitude=0.15`, `frequency=1.2`, `phase_spread=0.3` | Sine-driven horizontal shear |
| `shake` | `amp=3`, `freq=24`, `axis=Both/Horizontal/Vertical` | High-frequency jitter (damage, rage) |
| `tumble` | `amount=0.3`, `speed=1`, `perspective=1.5` | Pseudo-3D wobble |
| `rise` | `amount=20`, `dir=0` (degrees) | Slides in from an offset on intro |
| `scatter` | `distance=40` | Glyphs fly in from random directions |
| `pop` | `start_scale=0`, `fade_amount=0.8` | Scales in from nothing |
| `fade` | — | Fades in on intro, out on outro |
| `blur` | `radius=6`, `fade_amount=0.35` | Glyphs emerge from a blur on intro, dissolve back on outro — reveal is mostly blur, with a touch of alpha at the extremes |
| `shred` | `distance=24`, `slice=1`, `fade_amount=0.35` | Odd pixel rows slide left, even rows slide right with the reveal — glyphs tear apart and reassemble |
| `rainbow` | `speed=1`, `saturation=1`, `value=1`, `phase_spread=0.1` | Hue cycling across glyphs |
| `outline` | `[outline 3 black]`, `size=`, `color=` | Solid SDF outline (caps ~16px, see notes) |
| `glow` | `[glow orange]`, `size_px=6`, `thickness=0.38`, `intensity=0.8` | Soft halo, eased falloff |
| `shadow` | `[shadow 2 2]`, `x=`, `y=`, `spread=`, `shadow_color=` | Directional drop shadow |
| `tint` | `color=` | Fill color for the span |
| `size` | `[24]`, `[1.5]`, `size=`, `scale=` | Font size / scale mutations |

![Styling](doc/styling.png)

## Animation

Everything runs off one number: **`progress`** (`-1` = fully hidden, `0` = fully shown, `1` = hidden again through the outro).

```gdscript
label.play_intro()    # tween progress -1 → 0
label.play_outro()    # tween progress  0 → 1
label.seek(-0.4)      # jump to 60% revealed
```

- **Stagger** — `anim_intro_mode` / `anim_outro_mode`: `ALL`, `CHARACTER`, `WORD`, `LINE`, each with its own duration, tween, ease and `*_stagger` overlap.
- **Typewriter pauses** — `pause_on_punctuation` / `punctuation_pause` and `pause_on_newline` / `newline_pause` insert natural beats while revealing.
- **Autoplay** — `autoplay = INTRO` / `OUTRO` plays on ready; `loop_mode = LOOP` / `PING_PONG` drives `progress` forever without tweens.
- **Speed** — `time_scale` multiplies both effect animation and reveal tweens.
- **Signals** — `intro_finished`, `outro_finished`.
- The inspector has **Play Intro** / **Play Outro** buttons, and `progress` is scrubbable live in the editor.

Note: the label's `head` export (default `"fade"`) wraps all text in a span, so plain text fades in with intros. Set it to `""` to disable, or to `"blur"` / `"shred"` to make the whole label reveal through blur or the shredder effect.

![Blur and shredder reveals, underline/strikethrough](doc/reveal_fx.png)

## Links

```
[=https://godotengine.org]Godot homepage]
[=quest_42]Accept the quest]
```

```gdscript
label.clicked.connect(func(meta): print("clicked: ", meta))
label.hovered.connect(func(meta): ...)
label.alt_clicked.connect(func(meta): ...)   # right-click
label.unhovered.connect(func(meta): ...)
```

`meta` is the string after `=`, or the resolved Object when it names a node/instance id. If the target object implements `_rich_label_clicked(label)`, `_rich_label_hovered(label)`, `_rich_label_unhovered(label)` or `get_tooltip_text()`, those are called too (tooltips show automatically).

## Custom tags

Drop a GDScript file in `addons/rich_label/rl_tags/` — the filename is the tag name:

```gdscript
@tool
extends RichTag

@export var height := 6.0

func get_vertex() -> String:
    return """
    v.y += sin(TIME * 3.0 + seed * TAU) * %f * anim;
    """ % height
```

Available hooks: `get_vertex()` / `get_fragment()` (GLSL snippets; `v`, `it`/`intro_t`, `ot`/`outro_t`, `seed`, `origin`, `gsz` in vertex; `c`, `it`, `ot`, `seed` in fragment), `get_layer_count()` + `get_layer_config(i)` for outline/glow/shadow-style extra draw layers, `mutate_font()` / `mutate_font_size()` / `mutate_color()`, and `init_from_args()` for positional params. `TIME` in snippets is rewritten to the label's `fx_time` clock. See `rl_tags/wave.gd` and `rl_tags/outline.gd` for complete examples.

## Project settings

Under **Project Settings → General → rich_text** (enable *Advanced Settings* to see them):

| Setting | Default | Purpose |
|---|---|---|
| `rich_text/fonts_dir` | `res://assets/fonts` | `[font_id]` shorthands and font fallback |
| `rich_text/images_dir` | `res://assets/images` | `~image_id` lookup |
| `rich_text/scenes_dir` | `res://assets/scenes` | `~scene_id` lookup |

## Performance notes

- Glyphs draw as **one batched mesh per font texture** (`use_batched_mesh`, on by default) instead of thousands of `draw_char` calls.
- The generated shader is **hashed and cached** — editing text reuses the compiled shader when the tag set is unchanged.
- Effect state lives in uniform arrays sized to the glyph/layer count. Very long texts (thousands of glyphs × outline/glow layers) can exceed the uniform budget — the label logs a warning and suggests splitting across labels.
- Outlines past ~16px saturate the font atlas cell; raise it with more **Padding** / **MSDF Range** in the font's Import settings.
- MSDF fonts get SDF-crisp outlines/glow; bitmap fonts use a dilation fallback. Both paths are automatic.

## Running the tests

```sh
godot --headless --path . --import   # once, registers global classes
godot --headless --path . -s res://addons/rich_label/tests/smoke_test.gd
```

The smoke test exercises the parser, layout, shaping, shader generation, batching and the reveal API (`SMOKE OK` on success).

## Known issues

- `{expressions}` are evaluated with Godot's `Expression` against your `context` node and **can call its methods** — only bind contexts you trust.
- The shader identity encoding supports at most 31 distinct tag variants per label (GLSL `int` bitmask); beyond that the label logs a warning and extra tags share the last slot.
- Underline/strikethrough bars are extra quads in the label's batch mesh, so they ride the generated shader like glyphs: they wave, rainbow, fade and hover with the text, at zero CPU per-frame cost. Customize them with the `underline_color` / `strikethrough_color` (transparent = follow the glyph fill), `underline_thickness` / `strikethrough_thickness` (× font default) and `underline_offset` / `strikethrough_offset` (px, + = down) properties.
