## Fades alpha in on intro, out on outro.
## The simplest and most universally useful effect — stack it with anything.
@tool
extends RichTag

func get_fragment() -> String:
	return """c.a *= anim;"""
