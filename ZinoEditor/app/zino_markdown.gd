class_name ZinoMarkdown
extends RefCounted
## Minimal Markdown -> BBCode conversion for the in-app documentation viewer
## (headings, bold, inline code, code blocks, bullets, tables shown as monospace, links as text).

static func to_bbcode(md: String) -> String:
	var out := PackedStringArray()
	var in_code := false
	for raw in md.split("\n"):
		var line: String = raw.replace("[", "[lb]")
		if line.strip_edges().begins_with("```"):
			in_code = not in_code
			out.append("[code]" if in_code else "[/code]")
			continue
		if in_code:
			out.append(line)
			continue
		if line.begins_with("#### "):
			out.append("[b]%s[/b]" % _inline(line.substr(5)))
		elif line.begins_with("### "):
			out.append("\n[font_size=17][b]%s[/b][/font_size]" % _inline(line.substr(4)))
		elif line.begins_with("## "):
			out.append("\n[font_size=21][b][color=#ff7a45]%s[/color][/b][/font_size]" % _inline(line.substr(3)))
		elif line.begins_with("# "):
			out.append("[font_size=27][b]%s[/b][/font_size]" % _inline(line.substr(2)))
		elif line.strip_edges().begins_with("|"):
			if line.replace("|", "").replace("-", "").replace(":", "").strip_edges().is_empty():
				continue
			out.append("[code]%s[/code]" % line)
		elif line.strip_edges().begins_with("- ") or line.strip_edges().begins_with("* "):
			var indent := line.length() - line.strip_edges(true, false).length()
			out.append("%s•  %s" % ["    ".repeat(indent / 2), _inline(line.strip_edges().substr(2))])
		elif line.strip_edges() == "---":
			out.append("[color=#2a2f3a]────────────────────────────────────────[/color]")
		else:
			out.append(_inline(line))
	return "\n".join(out)

static func _inline(s: String) -> String:
	var r := RegEx.new()
	r.compile("\\*\\*(.+?)\\*\\*")
	s = r.sub(s, "[b]$1[/b]", true)
	r.compile("`([^`]+)`")
	s = r.sub(s, "[code][color=#f5b544]$1[/color][/code]", true)
	r.compile("\\[lb\\]([^\\]]+)\\]\\(([^)]+)\\)")
	s = r.sub(s, "[u]$1[/u]", true)
	return s
