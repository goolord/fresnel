// The preset info editor: name, author, category, tags and description of the current preset,
// saved with it. The categories offered are Config.categories (any may be typed).

open! Web

@set external setId: (element, string) => unit = "id"

let show = (ctx: Ctx.t) => {
  let stage = ctx.stage
  let meta = ctx.presets.current
  let dialog = Dialog.make(stage, "Preset info")
  let d = dialog.element

  let row = (label, input) => {
    let r = el("label", ~cls="drow", ~parent=d)
    el("span", ~text=label, ~parent=r)->ignore
    r->appendChild(input)
    input
  }
  let field = (label, value, ~placeholder="") => {
    let input = el("input")
    input->setValue(value)
    input->setPlaceholder(placeholder)
    row(label, input)
  }

  let name = field("name", meta.name)
  name->setMaxLength(Preset.maxNameLength)
  let author = field("author", meta.author)
  let category = field("category", meta.category, ~placeholder="e.g. pad")
  let list = el("datalist", ~parent=d)
  list->setId("preset-categories")
  Config.categories->Array.forEach(c => el("option", ~parent=list)->setValue(c))
  category->setAttribute("list", Str("preset-categories"))
  let tags = field("tags", meta.tags->Array.join(", "), ~placeholder="comma separated")
  let description = row("description", el("textarea"))
  description->setValue(meta.description)

  let close = () => dialog->Dialog.remove
  let save = () => {
    ctx.presets->PresetStore.setInfo({
      ...meta,
      name: name->value->String.trim,
      author: author->value->String.trim,
      category: category->value->String.trim,
      tags: Preset.parseTags(tags->value),
      description: description->value->String.trim,
    })
    close()
  }

  dialog->Dialog.finish([("OK", save), ("Cancel", close)], ~onEnter=save, ~close)->ignore
  name->focus
  name->select
}
